---
name: plantuml-links
description: Generates properly encoded PlantUML diagram links for online viewing. Use after creating .puml diagram files to generate viewable URLs.
---

# PlantUML Link Generator

## Purpose

Generate correctly encoded PlantUML URLs using Deflate + Custom Base64 encoding (NOT standard Base64).

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

## Important

- PlantUML uses custom encoding, NOT standard Base64
- Always regenerate links after diagram changes
- Test generated URLs before sharing
