// Minimal dependency-free static file server for verifying the GUI HTML/CSS in a
// real browser (preview tooling). Serves Development/gui/ ; "/" → paywall.html.
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { join, extname, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const GUI = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..", "gui");
const PORT = 8745;
const MIME = { ".html": "text/html", ".css": "text/css", ".js": "text/javascript",
  ".png": "image/png", ".svg": "image/svg+xml", ".ico": "image/x-icon", ".json": "application/json" };

createServer(async (req, res) => {
  let p = decodeURIComponent(new URL(req.url, "http://x").pathname);
  if (p === "/" || p === "") p = "/paywall.html";
  try {
    const data = await readFile(join(GUI, p));
    res.writeHead(200, { "Content-Type": MIME[extname(p)] || "application/octet-stream" });
    res.end(data);
  } catch {
    res.writeHead(404); res.end("not found");
  }
}).listen(PORT, () => console.log(`gui static server on http://localhost:${PORT}`));
