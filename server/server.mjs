// The Dict store as one small Node server, for Railway.
//
//   /                  landing page        (public/index.html)
//   /thanks            after checkout      (public/thanks.html)
//   /buy               → Stripe Payment Link
//   /api/license       ?session_id=cs_… → { key, activate, email }
//   /healthz           for Railway's health check
//
// The pages are tiny, so they're read once at startup and served from
// memory. Only files in public/ can be served, under fixed paths.
import { createServer } from "node:http";
import { readdirSync, readFileSync } from "node:fs";
import { extname, join } from "node:path";
import { GET as license } from "./api/license.mjs";
import { GET as buy } from "./api/buy.mjs";

const TYPES = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
};

const SECURITY_HEADERS = {
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
};

/** Maps URL paths to files in dir. "thanks.html" answers /thanks too. */
export function loadPages(dir) {
  const pages = new Map();
  for (const name of readdirSync(dir)) {
    const page = { body: readFileSync(join(dir, name)), type: TYPES[extname(name)] ?? "application/octet-stream" };
    pages.set("/" + name, page);
    if (name.endsWith(".html")) pages.set("/" + name.slice(0, -5), page);
    if (name === "index.html") pages.set("/", page);
  }
  return pages;
}

const ROUTES = { "/api/license": license, "/buy": buy };

export function createStore({ pages = loadPages(new URL("./public", import.meta.url).pathname), routes = ROUTES } = {}) {
  return createServer(async (req, res) => {
    const url = new URL(req.url, "http://" + (req.headers.host ?? "localhost"));
    try {
      if (req.method !== "GET" && req.method !== "HEAD") {
        res.writeHead(405, { Allow: "GET, HEAD", ...SECURITY_HEADERS }).end();
        return;
      }
      if (url.pathname === "/healthz") {
        res.writeHead(200, { "Content-Type": "text/plain", ...SECURITY_HEADERS }).end("ok");
        return;
      }
      const handler = routes[url.pathname];
      if (handler) {
        const response = await handler(new Request(url, { method: req.method, headers: req.headers }));
        res.writeHead(response.status, { ...Object.fromEntries(response.headers), ...SECURITY_HEADERS });
        res.end(req.method === "HEAD" ? undefined : Buffer.from(await response.arrayBuffer()));
        return;
      }
      const page = pages.get(url.pathname);
      if (page) {
        res.writeHead(200, { "Content-Type": page.type, "Cache-Control": "public, max-age=300", ...SECURITY_HEADERS });
        res.end(req.method === "HEAD" ? undefined : page.body);
        return;
      }
      res.writeHead(404, { "Content-Type": "text/plain", ...SECURITY_HEADERS }).end("Not found");
    } catch (error) {
      console.error(error);
      if (!res.headersSent) res.writeHead(500, { "Content-Type": "text/plain", ...SECURITY_HEADERS });
      res.end("Something went wrong.");
    }
  });
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const port = Number(process.env.PORT) || 3000;
  createStore().listen(port, () => console.log(`Dict store listening on ${port}`));
}
