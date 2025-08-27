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
    const { tool, arguments: args } = req.body;
    
    switch (tool) {
      case 'search':
        const searchResults = await searchClient.search(args.query, {
          top: args.top ?? 5,
          includeTotalCount: false,
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
        
        res.json({ 
          content: [{ type: "json", json: searchItems }] 
        });
        break;
        
      case 'fetch':
        const filter = `docId eq '${args.id.replace(/'/g, "''")}'`;
        const fetchResults = await searchClient.search("*", {
          filter,
          top: 1000
        });

        const fetchChunks: SearchDocument[] = [];
        for await (const r of fetchResults.results) {
          fetchChunks.push(r.document as SearchDocument);
        }

        let text = fetchChunks
          .filter(c => !args.pages || args.pages.includes(Number(c.page_number ?? 0)))
          .sort((a, b) => (a.page_number ?? 0) - (b.page_number ?? 0))
          .map(c => c.content_text ?? c.chunk ?? c.content ?? "")
          .join("\n\n");

        res.json({ 
          content: [{ type: "text", text }] 
        });
        break;
        
      default:
        res.status(400).json({ error: `Unknown tool: ${tool}` });
    }
  } catch (error) {
    console.error('Tool execution error:', error);
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
