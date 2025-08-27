// src/server.ts
import express, { Request, Response, NextFunction } from "express";
import cors from "cors";
import {
  SearchClient,
  AzureKeyCredential
} from "@azure/search-documents";

// Define the structure of our search documents
interface SearchDocument {
  id: string;
  title?: string;
  file_name?: string;
  chunk?: string;
  content?: string;
  content_text?: string;
  source_url?: string;
  page_number?: number;
  docId?: string;
}

const {
  SEARCH_ENDPOINT,
  SEARCH_KEY,
  SEARCH_INDEX,
  SERVER_API_KEY // API key for clients (sent as header)
} = process.env;

if (!SEARCH_ENDPOINT || !SEARCH_KEY || !SEARCH_INDEX || !SERVER_API_KEY) {
  throw new Error("Missing required env vars.");
}

const searchClient = new SearchClient<SearchDocument>(
  SEARCH_ENDPOINT,
  SEARCH_INDEX,
  new AzureKeyCredential(SEARCH_KEY)
);

// ---- Express App Setup ----
const app = express();
app.use(cors());
app.use(express.json());

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

// API key authentication for MCP endpoints
app.use('/api', (req: Request, res: Response, next: NextFunction) => {
  const key = req.header("x-api-key");
  if (key !== SERVER_API_KEY) return res.status(401).send("Unauthorized");
  next();
});

// Search endpoint - semantic search over indexed PDFs
app.post('/api/search', async (req: Request, res: Response) => {
  try {
    const { query, top = 5 } = req.body;
    
    if (!query) {
      return res.status(400).json({ error: 'Query parameter is required' });
    }

    const results = await searchClient.search(query, {
      top,
      includeTotalCount: false,
      // Remove the problematic vectorSearchOptions for now
    });

    const items: any[] = [];
    for await (const r of results.results) {
      const doc = r.document as SearchDocument;
      items.push({
        id: doc.id,
        title: doc.title ?? doc.file_name ?? doc.id,
        text: doc.content_text ?? doc.chunk ?? doc.content ?? "",
        url: doc.source_url ?? null,
        score: r.score
      });
    }
    
    res.json({ results: items });
  } catch (error) {
    console.error('Search error:', error);
    res.status(500).json({ 
      error: 'Search failed', 
      message: error instanceof Error ? error.message : 'Unknown error' 
    });
  }
});

// Fetch endpoint - return full text (or aggregate chunks) by doc id
app.post('/api/fetch', async (req: Request, res: Response) => {
  try {
    const { id, pages }: { id: string; pages?: number[] } = req.body;
    
    if (!id) {
      return res.status(400).json({ error: 'ID parameter is required' });
    }

    // Assume index stores per-chunk with a shared docId field; adjust to your schema
    const filter = `docId eq '${id.replace(/'/g, "''")}'`;
    const results = await searchClient.search("*", {
      filter,
      top: 1000
    });

    const chunks: SearchDocument[] = [];
    for await (const r of results.results) {
      chunks.push(r.document as SearchDocument);
    }

    // optional page filtering if you store page numbers in the index
    let text = chunks
      .filter(c => !pages || pages.includes(Number(c.page_number ?? 0)))
      .sort((a, b) => (a.page_number ?? 0) - (b.page_number ?? 0))
      .map(c => c.content_text ?? c.chunk ?? c.content ?? "")
      .join("\n\n");

    res.json({ text, chunks: chunks.length });
  } catch (error) {
    console.error('Fetch error:', error);
    res.status(500).json({ 
      error: 'Fetch failed', 
      message: error instanceof Error ? error.message : 'Unknown error' 
    });
  }
});

// MCP-style tools endpoint that accepts tool calls
app.post('/api/tools', async (req: Request, res: Response) => {
  try {
    console.log('Tools request body:', JSON.stringify(req.body, null, 2));
    
    // Handle MCP protocol initialization and handshake
    if (req.body.method === 'initialize') {
      console.log('Handling MCP initialize method');
      return res.json({
        jsonrpc: "2.0",
        id: req.body.id,
        result: {
          protocolVersion: "2025-06-18",
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
              description: "Retrieve full document content or specific pages",
              inputSchema: {
                type: "object",
                properties: {
                  id: {
                    type: "string",
                    description: "The document ID to fetch"
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
      
      console.log(`MCP tools/call - Tool: ${toolName}, Args:`, args);

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
          });
          
          const searchItems: any[] = [];
          for await (const r of searchResults.results) {
            const doc = r.document as SearchDocument;
            searchItems.push({
              id: doc.id,
              title: doc.title ?? doc.file_name ?? doc.id,
              text: doc.content_text ?? doc.chunk ?? doc.content ?? "",
              url: doc.source_url ?? null,
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

          if (!docId) {
            return res.status(400).json({
              jsonrpc: "2.0",
              id: req.body.id,
              error: {
                code: -32602,
                message: "Document ID is required"
              }
            });
          }

          const filter = `docId eq '${docId.replace(/'/g, "''")}'`;
          const fetchResults = await searchClient.search("*", {
            filter,
            top: 1000
          });

          const fetchChunks: SearchDocument[] = [];
          for await (const r of fetchResults.results) {
            fetchChunks.push(r.document as SearchDocument);
          }

          let text = fetchChunks
            .filter(c => !pages.length || pages.includes(Number(c.page_number ?? 0)))
            .sort((a, b) => (a.page_number ?? 0) - (b.page_number ?? 0))
            .map(c => c.content_text ?? c.chunk ?? c.content ?? "")
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

    console.log(`Legacy format - Tool: ${tool}, Args:`, args);

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
        });
        
        const searchItems: any[] = [];
        for await (const r of searchResults.results) {
          const doc = r.document as SearchDocument;
          searchItems.push({
            id: doc.id,
            title: doc.title ?? doc.file_name ?? doc.id,
            text: doc.content_text ?? doc.chunk ?? doc.content ?? "",
            url: doc.source_url ?? null,
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

        if (!docId) {
          return res.status(400).json({ error: 'Document ID is required for fetch' });
        }

        const filter = `docId eq '${docId.replace(/'/g, "''")}'`;
        const fetchResults = await searchClient.search("*", {
          filter,
          top: 1000
        });

        const fetchChunks: SearchDocument[] = [];
        for await (const r of fetchResults.results) {
          fetchChunks.push(r.document as SearchDocument);
        }

        let text = fetchChunks
          .filter(c => !pages.length || pages.includes(Number(c.page_number ?? 0)))
          .sort((a, b) => (a.page_number ?? 0) - (b.page_number ?? 0))
          .map(c => c.content_text ?? c.chunk ?? c.content ?? "")
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
          message: 'Internal error',
          data: error instanceof Error ? error.message : 'Unknown error'
        }
      });
    }
    
    // Return legacy error format
    res.status(500).json({ 
      error: 'Tool execution failed', 
      message: error instanceof Error ? error.message : 'Unknown error'
    });
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
