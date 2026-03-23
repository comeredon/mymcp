---
name: plantuml-links
description: Generates properly encoded PlantUML diagram links for online viewing. Use after creating .puml diagram files to generate viewable URLs.
---

# PlantUML Link Generator

> **Related skills:** `orchestration/diagram-verification`

## Purpose

Generate correctly encoded PlantUML URLs using Deflate + Custom Base64 encoding (NOT standard Base64).

**WARNING**: The `uml-mcp-azure` MCP server generates URLs with **INCORRECT encoding**. Its encoded data uses a different algorithm than what the PlantUML server expects. **Never use URLs returned by `uml-mcp-azure` directly.** Always re-encode from the `.puml` source files using the Python script below.

## Python Script

Save as `docs/diagrams/generate_links.py`:

```python
import zlib, os, glob

def plantuml_encode(text):
    compressed = zlib.compress(text.encode('utf-8'))[2:-4]
    return encode64(compressed)

def encode64(data):
    res = ""
    for i in range(0, len(data), 3):
        b1, b2, b3 = data[i], (data[i+1] if i+1 < len(data) else 0), (data[i+2] if i+2 < len(data) else 0)
        c1, c2, c3, c4 = b1 >> 2, ((b1 & 0x3) << 4) | (b2 >> 4), ((b2 & 0xF) << 2) | (b3 >> 6), b3 & 0x3F
        if i+1 >= len(data): c3 = c4 = 64
        elif i+2 >= len(data): c4 = 64
        res += encode6bit(c1) + encode6bit(c2) + encode6bit(c3) + encode6bit(c4)
    return res

def encode6bit(b):
    if b < 10: return chr(48 + b)
    b -= 10
    if b < 26: return chr(65 + b)
    b -= 26
    if b < 26: return chr(97 + b)
    b -= 26
    return '-' if b == 0 else '_' if b == 1 else '?'
```

## Usage

```bash
cd docs/diagrams
python generate_links.py > DIAGRAM_LINKS.md
```

## CRITICAL: URL Generation Rules

### 1. Never use `uml-mcp-azure` URLs directly

The `uml-mcp-azure` MCP server returns URLs with **broken encoding** (wrong algorithm). These URLs will fail even with a `~1` prefix. Always re-encode from `.puml` source files using the Python script above.

### 2. Always add `~1` prefix

The PlantUML server requires `~1` before DEFLATE-encoded data. The `generate_url()` function below includes it automatically:

```python
def generate_url(puml_text, fmt="svg"):
    encoded = plantuml_encode(puml_text)
    return f"http://www.plantuml.com/plantuml/{fmt}/~1{encoded}"
```

### 3. Always verify URLs render

After generating URLs, test each one returns `<svg` content:

```python
import urllib.request
req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
resp = urllib.request.urlopen(req, timeout=20)
assert b"<svg" in resp.read(500)
```

### Workflow Summary

```
.puml source file
       │
       ▼
Python zlib.compress()[2:-4] + custom base64 (encode6bit)
       │
       ▼
Prepend ~1 → http://www.plantuml.com/plantuml/svg/~1<encoded>
       │
       ▼
Verify <svg> response → publish URL
```
