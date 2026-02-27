// src/server.ts
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
    page_number?: number;
    bounding_polygons?: string;
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
  if (!apiKey || apiKey !== SERVER_API_KEY) {
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

    const sanitizedTop = Math.min(Math.max(Number(top) || 5, 1), 20);

    const results = await searchClient.search(query, {
      top: sanitizedTop,
      includeTotalCount: false,
      queryType: "semantic",
      semanticSearchOptions: { configurationName: "semantic-config" },
      vectorSearchOptions: {
        queries: [{ kind: "text", text: query, kNearestNeighborsCount: sanitizedTop, fields: ["content_embedding"] }]
      },
      select: ["content_id", "text_document_id", "image_document_id", "document_title", "content_text", "content_path", "location_metadata"]
    });

    const items: any[] = [];
    for await (const r of results.results) {
      const doc = r.document as SearchDocument;
      items.push({
        id: doc.content_id,
        documentId: doc.text_document_id ?? null,
        title: doc.document_title ?? doc.content_id,
        text: doc.content_text ?? "",
        type: doc.image_document_id ? "image" : "text",
        imagePath: doc.content_path ?? null,
        pageNumber: doc.location_metadata?.page_number ?? null,
        score: r.score
      });
    }
    
    res.json({ results: items });
  } catch (error) {
    console.error('Search error:', error);
    res.status(500).json({ error: 'Search failed' });
  }
});

// Fetch endpoint - return full text (or aggregate chunks) by document title or text_document_id
app.post('/api/fetch', authenticateApiKey, async (req: Request, res: Response) => {
  try {
    const { id, pages }: { id: string; pages?: number[] } = req.body;
    
    if (!id || typeof id !== 'string') {
      return res.status(400).json({ error: 'ID parameter is required and must be a string' });
    }

    // Validate id format - only allow alphanumeric, hyphens, underscores, dots
    if (!/^[\w.\-]+$/.test(id)) {
      return res.status(400).json({ error: 'Invalid document ID format' });
    }

    // Try fetching by text_document_id first, then fall back to document_title
    let chunks: SearchDocument[] = [];
    for (const filterExpr of [
      `text_document_id eq '${id}'`,
      `document_title eq '${id}'`
    ]) {
      const results = await searchClient.search("*", {
        filter: filterExpr,
        top: 500,
        select: ["content_id", "text_document_id", "document_title", "content_text", "location_metadata"]
      });
      for await (const r of results.results) {
        chunks.push(r.document as SearchDocument);
      }
      if (chunks.length > 0) break;
    }

    let text = chunks
      .filter(c => !pages || pages.includes(Number(c.location_metadata?.page_number ?? 0)))
      .sort((a, b) => (a.location_metadata?.page_number ?? 0) - (b.location_metadata?.page_number ?? 0))
      .map(c => c.content_text ?? "")
      .join("\n\n");

    res.json({ text, chunks: chunks.length });
  } catch (error) {
    console.error('Fetch error:', error);
    res.status(500).json({ error: 'Fetch failed' });
  }
});

// MCP-style tools endpoint that accepts tool calls
app.post('/api/tools', authenticateApiKey, async (req: Request, res: Response) => {
  try {
    console.log('Tools request body:', JSON.stringify(req.body, null, 2));
    
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
      
      console.log("MCP tools/call - Tool: %s, Args:", toolName, args);

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
        case 'search':
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

          const searchResults = await searchClient.search(query, {
            top: Math.min(top, 20),
            includeTotalCount: true,
            queryType: "semantic",
            semanticSearchOptions: { configurationName: "semantic-config" },
            vectorSearchOptions: {
              queries: [{ kind: "text", text: query, kNearestNeighborsCount: Math.min(top, 20), fields: ["content_embedding"] }]
            },
            select: ["content_id", "text_document_id", "image_document_id", "document_title", "content_text", "content_path", "location_metadata"]
          });
          
          const searchItems: any[] = [];
          for await (const r of searchResults.results) {
            const doc = r.document as SearchDocument;
            searchItems.push({
              id: doc.content_id,
              documentId: doc.text_document_id ?? null,
              title: doc.document_title ?? doc.content_id,
              text: doc.content_text ?? "",
              type: doc.image_document_id ? "image" : "text",
              imagePath: doc.content_path ?? null,
              pageNumber: doc.location_metadata?.page_number ?? null,
              score: r.score
            });
          }

          return res.json({
            jsonrpc: "2.0",
            id: req.body.id,
            result: {
              content: [
                {
                  type: "text",
                  text: `Found ${searchItems.length} results for "${query}":\n\n` +
                        searchItems.map((item, index) => 
                          `${index + 1}. ${item.title}\n${item.text.substring(0, 500)}...\n`
                        ).join('\n')
                }
              ]
            }
          });
          
        case 'fetch':
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

          // Try fetching by text_document_id first, then fall back to document_title
          const fetchChunks: SearchDocument[] = [];
          for (const filterExpr of [
            `text_document_id eq '${docId}'`,
            `document_title eq '${docId}'`
          ]) {
            const fetchResults = await searchClient.search("*", {
              filter: filterExpr,
              top: 500,
              select: ["content_id", "text_document_id", "document_title", "content_text", "location_metadata"]
            });
            for await (const r of fetchResults.results) {
              fetchChunks.push(r.document as SearchDocument);
            }
            if (fetchChunks.length > 0) break;
          }

          let text = fetchChunks
            .filter(c => !pages.length || pages.includes(Number(c.location_metadata?.page_number ?? 0)))
            .sort((a, b) => (a.location_metadata?.page_number ?? 0) - (b.location_metadata?.page_number ?? 0))
            .map(c => c.content_text ?? "")
            .join("\n\n");

          return res.json({
            jsonrpc: "2.0",
            id: req.body.id,
            result: {
              content: [
                {
                  type: "text",
                  text: text || "No content found for the specified document ID."
                }
              ]
            }
          });
          
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

    console.log("Legacy format - Tool: %s, Args:", tool, args);

    // Handle legacy format requests
    switch (tool.toLowerCase()) {
      case 'search':
        const query = args.query || args.q || '';
        const top = args.top || args.count || 5;
        
        if (!query) {
          return res.status(400).json({ error: 'Search query is required' });
        }

        const searchResults = await searchClient.search(query, {
          top: Math.min(top, 20),
          includeTotalCount: true,
          queryType: "semantic",
          semanticSearchOptions: { configurationName: "semantic-config" },
          vectorSearchOptions: {
            queries: [{ kind: "text", text: query, kNearestNeighborsCount: Math.min(top, 20), fields: ["content_embedding"] }]
          },
          select: ["content_id", "text_document_id", "image_document_id", "document_title", "content_text", "content_path", "location_metadata"]
        });
        
        const searchItems: any[] = [];
        for await (const r of searchResults.results) {
          const doc = r.document as SearchDocument;
          searchItems.push({
            id: doc.content_id,
            title: doc.document_title ?? doc.content_id,
            text: doc.content_text ?? "",
            type: doc.image_document_id ? "image" : "text",
            imagePath: doc.content_path ?? null,
            pageNumber: doc.location_metadata?.page_number ?? null,
            score: r.score
          });
        }

        return res.json({ 
          query: query,
          total: searchItems.length,
          results: searchItems 
        });
        
      case 'fetch':
        const docId = args.id || args.document_id || '';
        const pages = args.pages || [];

        if (!docId || typeof docId !== 'string') {
          return res.status(400).json({ error: 'Document ID is required for fetch' });
        }

        if (!/^[\w.\-]+$/.test(docId)) {
          return res.status(400).json({ error: 'Invalid document ID format' });
        }

        const filter = `text_document_id eq '${docId}'`;
        const fetchResults = await searchClient.search("*", {
          filter,
          top: 500
        });

        const fetchChunks: SearchDocument[] = [];
        for await (const r of fetchResults.results) {
          fetchChunks.push(r.document as SearchDocument);
        }

        let text = fetchChunks
          .filter(c => !pages.length || pages.includes(Number(c.location_metadata?.page_number ?? 0)))
          .sort((a, b) => (a.location_metadata?.page_number ?? 0) - (b.location_metadata?.page_number ?? 0))
          .map(c => c.content_text ?? "")
          .join("\n\n");

        const fetchResult = {
          id: docId,
          text: text,
          chunks: fetchChunks.length,
          pages: pages
        };

        return res.json(fetchResult);
        
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
