import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import worker from "../dist/server/index.js";

// Serve the actual production bundle locally. Normalize filesystem separators
// explicitly so static assets work on Windows and OneDrive workspaces.
const assetRoot = fileURLToPath(new URL("../dist/client/", import.meta.url));
const types = { ".css": "text/css", ".js": "text/javascript", ".mjs": "text/javascript", ".json": "application/json", ".png": "image/png", ".webp": "image/webp", ".svg": "image/svg+xml", ".woff2": "font/woff2", ".woff": "font/woff", ".ico": "image/x-icon" };
async function asset(request) {
  let pathname;
  try { pathname = decodeURIComponent(new URL(request.url).pathname); } catch { return new Response("Bad request", { status: 400 }); }
  const target = path.resolve(assetRoot, `.${pathname}`);
  if (!target.startsWith(path.resolve(assetRoot) + path.sep) || pathname.includes("\\") || pathname.startsWith("/.")) return new Response("Not found", { status: 404 });
  try {
    if (!(await stat(target)).isFile()) return new Response("Not found", { status: 404 });
    return new Response(request.method === "HEAD" ? null : await readFile(target), { headers: { "content-type": types[path.extname(target)] ?? "application/octet-stream", "cache-control": "no-cache" } });
  } catch { return new Response("Not found", { status: 404 }); }
}
const port = Number(process.env.PORT || 3000);
createServer(async (req, res) => {
  try {
    if (!["GET", "HEAD"].includes(req.method)) { res.writeHead(405); res.end(); return; }
    const request = new Request(new URL(req.url, `http://127.0.0.1:${port}`), { method: req.method, headers: { ...req.headers, host: `localhost:${port}` } });
    let response = await asset(request);
    if (response.status === 404) response = await worker.fetch(request, { ASSETS: { fetch: asset } }, { waitUntil(promise) { Promise.resolve(promise).catch(console.error); }, passThroughOnException() {} });
    res.writeHead(response.status, Object.fromEntries(response.headers));
    res.end(req.method === "HEAD" ? undefined : Buffer.from(await response.arrayBuffer()));
  } catch (error) { console.error(error); res.writeHead(500); res.end("Preview could not render this page."); }
}).listen(port, "127.0.0.1", () => console.log(`Content Maker production preview: http://127.0.0.1:${port}`));
