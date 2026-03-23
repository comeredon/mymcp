// src/server.ts
import crypto from "crypto";
import express, { Request, Response, NextFunction } from "express";
import cors from "cors";
import helmet from "helmet";
import rateLimit from "express-rate-limit";
import { DefaultAzureCredential } from "@azure/identity";
import { SearchClient } from "@azure/search-documents";

// Define the structure of our search documents
interface SearchDocument {
  content_id: string;
  text_document_id?: string;
  image_document_id?: string;
  document_title?: string;
  content_text?: string;
  content_path?: string;
  location_metadata?: {
    pageNumberFrom?: number;
    pageNumberTo?: number;
    ordinalPosition?: number;
    source?: string;
  };
  // Vector field: not retrievable in results but required for vector search query field targeting
  content_embedding?: number[];
}

const {
  SEARCH_ENDPOINT,
  SEARCH_INDEX
} = process.env;

if (!SEARCH_ENDPOINT || !SEARCH_INDEX) {
  throw new Error("Missing required env vars: SEARCH_ENDPOINT, SEARCH_INDEX");
}

const searchClient = new SearchClient<SearchDocument>(
  SEARCH_ENDPOINT,
  SEARCH_INDEX,
  new DefaultAzureCredential()
);

// Build an OData page filter clause that matches chunks covering any of the requested pages.
// A chunk covers page P when pageNumberFrom <= P AND pageNumberTo >= P.
function buildPageFilter(pages?: number[]): string {
  if (!pages || pages.length === 0) return '';
  return pages.map(p =>
    `(location_metadata/pageNumberFrom le ${p} and location_metadata/pageNumberTo ge ${p})`
  ).join(' or ');
}

// Combine a base filter with an optional page filter using AND
function combineFilters(base: string, pageFilter: string): string {
  if (!pageFilter) return base;
  return `(${base}) and (${pageFilter})`;
}

// Fetch all matching documents, ordered by page and ordinal position.
// Azure AI Search caps $top at 1000 (platform limit). Documents with more
// than 1000 chunks would require skip-based pagination — not implemented
// yet since current documents are well below that threshold (pg.pdf = 810).
async function fetchAllDocuments(filter: string, maxResults?: number): Promise<SearchDocument[]> {
  const docs: SearchDocument[] = [];
  const results = await searchClient.search("*", {
    filter,
    top: maxResults ?? 1000,
    orderBy: ["location_metadata/pageNumberFrom asc", "location_metadata/ordinalPosition asc"],
    select: ["content_id", "text_document_id", "document_title", "content_text", "content_path", "location_metadata"]
  });
  for await (const r of results.results) {
    docs.push(r.document as SearchDocument);
  }
  return docs;
}

// ---- Shared result types ----
interface SearchResultItem {
  id: string;
  title: string;
  text: string;
  documentId: string | null;
  type: string;
  imagePath: string | null;
  pageNumber: number | null;
  score?: number;
}

interface ChunkDetail {
  id: string;
  text: string;
  type: 'text' | 'image';
  pageFrom: number | null;
  pageTo: number | null;
  ordinal: number | null;
}

interface ImageDetail {
  id: string;
  description: string;
  pageFrom: number | null;
  pageTo: number | null;
  ordinal: number | null;
}

interface FetchResult {
  text: string;
  images: ImageDetail[];
  textChunks: number;
  imageChunks: number;
  chunkDetails: ChunkDetail[];
}

// Core search implementation — single source of truth for search logic.
async function performSearch(query: string, top: number = 5): Promise<SearchResultItem[]> {
  const sanitizedTop = Math.min(Math.max(Number(top) || 5, 1), 20);
  // kNearestNeighborsCount floored at 50 for better hybrid search recall (MS recommendation)
  const knn = Math.min(Math.max(sanitizedTop * 3, 50), 150);

  const results = await searchClient.search(query, {
    top: sanitizedTop,
    includeTotalCount: true,
    queryType: "semantic",
    semanticSearchOptions: { configurationName: "semantic-config" },
    vectorSearchOptions: {
      queries: [{ kind: "text", text: query, kNearestNeighborsCount: knn, fields: ["content_embedding"] }]
    },
    select: ["content_id", "text_document_id", "image_document_id", "document_title", "content_text", "content_path", "location_metadata"]
  });

  const items: SearchResultItem[] = [];
  for await (const r of results.results) {
    const doc = r.document as SearchDocument;
    items.push({
      id: doc.content_id,
      title: doc.document_title ?? doc.content_id,
      text: doc.content_text ?? "",
      documentId: doc.text_document_id ?? null,
      type: doc.image_document_id ? "image" : "text",
      imagePath: doc.content_path ?? null,
      pageNumber: doc.location_metadata?.pageNumberFrom ?? null,
      score: r.score
    });
  }
  return items;
}

// Core fetch implementation — single source of truth for fetch logic.
// When no pages are specified the full document is returned (all chunks, server-ordered).
async function performFetch(id: string, pages?: number[]): Promise<FetchResult> {
  const pageFilter = buildPageFilter(pages);
  let chunks: SearchDocument[] = [];
  for (const baseFilter of [
    `text_document_id eq '${id}'`,
    `document_title eq '${id}'`
  ]) {
    chunks = await fetchAllDocuments(combineFilters(baseFilter, pageFilter));
    if (chunks.length > 0) break;
  }

  // Results are already ordered by pageNumberFrom, ordinalPosition via
  // the orderBy clause in fetchAllDocuments — no client-side sort needed.

  // Classify each chunk as text or image based on content pattern
  const details: ChunkDetail[] = chunks.map(c => {
    const content = c.content_text ?? "";
    const chunkType: 'text' | 'image' = content.startsWith('The image') ? 'image' : 'text';
    return {
      id: c.content_id,
      text: content,
      type: chunkType,
      pageFrom: c.location_metadata?.pageNumberFrom ?? null,
      pageTo: c.location_metadata?.pageNumberTo ?? null,
      ordinal: c.location_metadata?.ordinalPosition ?? null
    };
  });

  // Separate text and image chunks
  const textDetails = details.filter(d => d.type === 'text');
  const imageDetails = details.filter(d => d.type === 'image');

  // Deduplicate the 200-char overlap produced by Content Understanding's
  // chunkingProperties (maximumLength: 2000, overlapLength: 200).
  // Each type is now processed independently since they're separated.
  function deduplicateChunks(chunks: ChunkDetail[]): string[] {
    const parts: string[] = [];
    let prevText = '';
    for (const chunk of chunks) {
      let text = chunk.text;
      if (prevText && text.length > 0) {
        // Find the longest suffix of prevText that is a prefix of text (up to 300 chars)
        const maxCheck = Math.min(300, prevText.length, text.length);
        let overlapLen = 0;
        for (let size = maxCheck; size > 0; size--) {
          if (prevText.endsWith(text.substring(0, size))) {
            overlapLen = size;
            break;
          }
        }
        if (overlapLen > 0) {
          text = text.substring(overlapLen);
        }
      }
      prevText = chunk.text; // store original for next comparison
      parts.push(text);
    }
    return parts;
  }

  const dedupedText = deduplicateChunks(textDetails).join("\n\n");

  // Build image details — no dedup needed for images (descriptions are unique per figure)
  const images: ImageDetail[] = imageDetails.map(d => ({
    id: d.id,
    description: d.text,
    pageFrom: d.pageFrom,
    pageTo: d.pageTo,
    ordinal: d.ordinal
  }));

  return {
    text: dedupedText,
    images,
    textChunks: textDetails.length,
    imageChunks: imageDetails.length,
    chunkDetails: details
  };
}

// Format a page label from chunk page range
function pageLabel(pageFrom: number | null, pageTo: number | null): string {
  if (pageFrom == null) return 'Unknown page';
  if (pageTo == null || pageTo === pageFrom) return `Page ${pageFrom}`;
  return `Pages ${pageFrom}–${pageTo}`;
}

// Format fetch results as structured markdown text for MCP tool consumers.
function formatFetchAsText(id: string, result: FetchResult, pages?: number[]): string {
  const totalChunks = result.textChunks + result.imageChunks;
  if (totalChunks === 0) {
    return `No content found for document "${id}"` +
      (pages && pages.length > 0 ? ` (requested pages: ${pages.join(', ')})` : '') + '.';
  }

  const pageNums = result.chunkDetails
    .map(d => d.pageFrom)
    .filter((p): p is number => p != null);
  const minPage = pageNums.length > 0 ? Math.min(...pageNums) : null;
  const maxPageTo = result.chunkDetails
    .map(d => d.pageTo ?? d.pageFrom)
    .filter((p): p is number => p != null);
  const maxPage = maxPageTo.length > 0 ? Math.max(...maxPageTo) : null;

  let header = `# ${id}\n`;
  header += `${result.textChunks} text chunks, ${result.imageChunks} image chunks`;
  if (minPage != null && maxPage != null) {
    header += `, covering pages ${minPage}–${maxPage}`;
  }
  if (pages && pages.length > 0) {
    header += ` (filtered to pages: ${pages.join(', ')})`;
  }
  header += '\n';

  // Text content section — deduplicated continuous text with page headers
  const textChunks = result.chunkDetails.filter(d => d.type === 'text');
  let textSection = '';
  if (textChunks.length > 0) {
    const textBody = textChunks.map(d => {
      const label = pageLabel(d.pageFrom, d.pageTo);
      return `### ${label}\n\n${d.text}`;
    }).join('\n\n');
    textSection = `## Text Content\n\n${textBody}`;
  }

  // Images section — figure descriptions with page references
  let imageSection = '';
  if (result.images.length > 0) {
    const imageBody = result.images.map(img => {
      const label = pageLabel(img.pageFrom, img.pageTo);
      return `- **${label}**: ${img.description}`;
    }).join('\n');
    imageSection = `## Images\n\n${imageBody}`;
  }

  const sections = [header, textSection, imageSection].filter(s => s.length > 0);
  return sections.join('\n\n');
}

// Format search results as structured markdown text for MCP tool consumers.
function formatSearchAsText(query: string, items: SearchResultItem[]): string {
  if (items.length === 0) {
    return `No results found for "${query}".`;
  }

  const header = `Found ${items.length} results for "${query}":\n`;
  const body = items.map((item, i) => {
    const meta = [
      `page: ${item.pageNumber ?? 'N/A'}`,
      `score: ${item.score?.toFixed(4) ?? 'N/A'}`,
      `type: ${item.type}`,
      `documentId: ${item.documentId ?? 'N/A'}`
    ].join(', ');
    const snippet = item.text.length > 1500
      ? item.text.substring(0, 1500) + '...'
      : item.text;
    return `${i + 1}. **${item.title}** (${meta})\n${snippet}`;
  }).join('\n\n');

  return `${header}\n${body}`;
}

// ---- Express App Setup ----
const app = express();

// Security headers
app.use(helmet());

// Rate limiting - 100 requests per minute per IP
const limiter = rateLimit({
  windowMs: 60 * 1000,
  max: 100,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests, please try again later.' }
});
app.use(limiter);

app.use(cors({ origin: process.env.ALLOWED_ORIGINS ? process.env.ALLOWED_ORIGINS.split(',') : [] }));
app.use(express.json({ limit: '1mb' }));

// API key authentication middleware (skip for health check)
const SERVER_API_KEY = process.env.SERVER_API_KEY;
function authenticateApiKey(req: Request, res: Response, next: NextFunction): void {
  if (!SERVER_API_KEY) {
    // If no key is configured, deny access (fail-closed)
    res.status(503).json({ error: 'Server not configured for authentication' });
    return;
  }
  const apiKey = req.headers['x-api-key'] as string;
  if (!apiKey) {
    res.status(401).json({ error: 'Unauthorized' });
    return;
  }
  // Timing-safe comparison to prevent timing attacks (OWASP A07)
  const expected = Buffer.from(SERVER_API_KEY);
  const provided = Buffer.from(apiKey);
  if (expected.length !== provided.length || !crypto.timingSafeEqual(expected, provided)) {
    res.status(401).json({ error: 'Unauthorized' });
    return;
  }
  next();
}

// Health check endpoint (no auth required)
app.get('/health', async (req: Request, res: Response) => {
  try {
    // Simple health check - could be enhanced to check Azure AI Search connectivity
    res.status(200).json({ 
      status: 'healthy', 
      timestamp: new Date().toISOString(),
      service: 'mcp-azure-pdf'
    });
  } catch (error) {
    res.status(503).json({ 
      status: 'unhealthy', 
      timestamp: new Date().toISOString(),
      error: error instanceof Error ? error.message : 'Unknown error'
    });
  }
});

// Search endpoint - semantic search over indexed PDFs
app.post('/api/search', authenticateApiKey, async (req: Request, res: Response) => {
  try {
    const { query, top = 5 } = req.body;
    
    if (!query || typeof query !== 'string') {
      return res.status(400).json({ error: 'Query parameter is required and must be a string' });
    }

    if (query.length > 1000) {
      return res.status(400).json({ error: 'Query must be 1000 characters or fewer' });
    }

    const items = await performSearch(query, top);
    res.json({ results: items });
  } catch (error) {
    console.error('Search error:', error);
    res.status(500).json({ error: 'Search failed' });
  }
});

// Fetch endpoint - return full text (or aggregate chunks) by document title (e.g. 'mg.pdf') or text_document_id
app.post('/api/fetch', authenticateApiKey, async (req: Request, res: Response) => {
  try {
    const { id, pages }: { id: string; pages?: number[] } = req.body;
    
    if (!id || typeof id !== 'string') {
      return res.status(400).json({ error: 'ID parameter is required and must be a string' });
    }

    if (!/^[\w.\-]+$/.test(id)) {
      return res.status(400).json({ error: 'Invalid document ID format' });
    }

    const result = await performFetch(id, pages);
    res.json({ id, ...result, pages });
  } catch (error) {
    console.error('Fetch error:', error);
    res.status(500).json({ error: 'Fetch failed' });
  }
});

// MCP-style tools endpoint that accepts tool calls
app.post('/api/tools', authenticateApiKey, async (req: Request, res: Response) => {
  try {
    // Handle MCP protocol initialization and handshake
    if (req.body.method === 'initialize') {
      console.log('Handling MCP initialize method');
      return res.json({
        jsonrpc: "2.0",
        id: req.body.id,
        result: {
          protocolVersion: "2024-11-05",
          capabilities: {
            tools: {},
            logging: {}
          },
          serverInfo: {
            name: "custom-pli-mcp",
            version: "1.0.0"
          }
        }
      });
    }

    // Handle MCP initialized notification
    if (req.body.method === 'notifications/initialized') {
      console.log('Handling MCP initialized notification');
      return res.status(200).send(); // Just acknowledge with 200 OK
    }

    // Handle logging/setLevel method
    if (req.body.method === 'logging/setLevel') {
      console.log('Handling MCP logging/setLevel method');
      return res.json({
        jsonrpc: "2.0",
        id: req.body.id,
        result: {}
      });
    }

    // Handle any other logging notifications
    if (req.body.method && req.body.method.startsWith('notifications/')) {
      console.log(`Handling MCP notification: ${req.body.method}`);
      return res.status(200).send(); // Just acknowledge with 200 OK
    }

    // Handle tools/list method
    if (req.body.method === 'tools/list') {
      console.log('Handling MCP tools/list method');
      return res.json({
        jsonrpc: "2.0",
        id: req.body.id,
        result: {
          tools: [
            {
              name: "search",
              description: "Search across indexed PDF documents using semantic search",
              inputSchema: {
                type: "object",
                properties: {
                  query: {
                    type: "string",
                    description: "The search query to find relevant content"
                  },
                  top: {
                    type: "number",
                    description: "Number of results to return (default: 5)",
                    default: 5
                  }
                },
                required: ["query"]
              }
            },
            {
              name: "fetch",
              description: "Retrieve full document content or specific pages by document title (e.g. 'mg.pdf') or documentId from search results",
              inputSchema: {
                type: "object",
                properties: {
                  id: {
                    type: "string",
                    description: "The document title (e.g. 'mg.pdf') or documentId returned by the search tool"
                  },
                  pages: {
                    type: "array",
                    items: { type: "number" },
                    description: "Specific page numbers to retrieve (optional)"
                  }
                },
                required: ["id"]
              }
            }
          ]
        }
      });
    }

    // Handle tools/call method (the main tool execution)
    if (req.body.method === 'tools/call') {
      const toolName = req.body.params?.name;
      const args = req.body.params?.arguments || {};
      
      console.log("MCP tools/call - Tool: %s", toolName);

      if (!toolName) {
        return res.status(400).json({
          jsonrpc: "2.0",
          id: req.body.id,
          error: {
            code: -32602,
            message: "Tool name is required in params.name"
          }
        });
      }

      switch (toolName.toLowerCase()) {
        case 'search': {
          const query = args.query || '';
          const top = args.top || 5;
          
          if (!query) {
            return res.status(400).json({
              jsonrpc: "2.0",
              id: req.body.id,
              error: {
                code: -32602,
                message: "Search query is required"
              }
            });
          }

          const searchItems = await performSearch(query, top);

          return res.json({
            jsonrpc: "2.0",
            id: req.body.id,
            result: {
              content: [
                {
                  type: "text",
                  text: formatSearchAsText(query, searchItems)
                }
              ]
            }
          });
        }
          
        case 'fetch': {
          const docId = args.id || '';
          const pages = args.pages || [];

          if (!docId || typeof docId !== 'string') {
            return res.status(400).json({
              jsonrpc: "2.0",
              id: req.body.id,
              error: {
                code: -32602,
                message: "Document ID is required"
              }
            });
          }

          if (!/^[\w.\-]+$/.test(docId)) {
            return res.status(400).json({
              jsonrpc: "2.0",
              id: req.body.id,
              error: {
                code: -32602,
                message: "Invalid document ID format"
              }
            });
          }

          const fetchResult = await performFetch(docId, pages);

          return res.json({
            jsonrpc: "2.0",
            id: req.body.id,
            result: {
              content: [
                {
                  type: "text",
                  text: formatFetchAsText(docId, fetchResult, pages)
                }
              ]
            }
          });
        }
          
        default:
          return res.status(400).json({
            jsonrpc: "2.0", 
            id: req.body.id,
            error: {
              code: -32601,
              message: `Unknown tool: ${toolName}. Available tools: search, fetch`
            }
          });
      }
    }

    // Legacy format support (for backward compatibility)
    let tool: string;
    let args: any;
    
    if (req.body.tool) {
      // Custom format: { tool: "search", arguments: {...} }
      tool = req.body.tool;
      args = req.body.arguments || {};
    } else if (req.body.name) {
      // Alternative format: { name: "search", arguments: {...} }
      tool = req.body.name;
      args = req.body.arguments || {};
    } else if (req.body.query) {
      // Default to search if no tool specified but query provided
      tool = 'search';
      args = { query: req.body.query, top: req.body.top || 5 };
    } else {
      return res.status(400).json({ 
        error: 'Unsupported request format. Expected MCP protocol format or legacy format.',
        received: req.body
      });
    }

    console.log("Legacy format - Tool: %s", tool);

    // Handle legacy format requests
    switch (tool.toLowerCase()) {
      case 'search': {
        const query = args.query || args.q || '';
        const top = args.top || args.count || 5;
        
        if (!query) {
          return res.status(400).json({ error: 'Search query is required' });
        }

        const searchItems = await performSearch(query, top);

        return res.json({ 
          query: query,
          total: searchItems.length,
          results: searchItems 
        });
      }
        
      case 'fetch': {
        const docId = args.id || args.document_id || '';
        const pages = args.pages || [];

        if (!docId || typeof docId !== 'string') {
          return res.status(400).json({ error: 'Document ID is required for fetch' });
        }

        if (!/^[\w.\-]+$/.test(docId)) {
          return res.status(400).json({ error: 'Invalid document ID format' });
        }

        const fetchResult = await performFetch(docId, pages);

        return res.json({ id: docId, ...fetchResult, pages });
      }
        
      default:
        return res.status(400).json({ 
          error: `Unknown tool: ${tool}. Available tools: search, fetch`,
          availableTools: ['search', 'fetch']
        });
    }
  } catch (error) {
    console.error('Tool execution error:', error);
    
    // Return MCP error format if it's an MCP request
    if (req.body.jsonrpc === "2.0") {
      return res.status(500).json({
        jsonrpc: "2.0",
        id: req.body.id,
        error: {
          code: -32603,
          message: 'Internal error'
        }
      });
    }
    
    // Return legacy error format
    res.status(500).json({ error: 'Tool execution failed' });
  }
});

const port = process.env.PORT || 8080;
app.listen(port, () => {
  console.log(`MCP server listening on :${port}`);
  console.log(`Health check available at http://localhost:${port}/health`);
  console.log(`Search API available at http://localhost:${port}/api/search`);
  console.log(`Fetch API available at http://localhost:${port}/api/fetch`);
  console.log(`Tools API available at http://localhost:${port}/api/tools`);
});
