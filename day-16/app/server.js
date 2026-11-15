// A small web app with deliberate bugs (slide 317): it can crash, freeze, or burn CPU.
// No dependencies: only Node's built-in http module.
const http = require("node:http");
const os = require("node:os");

const PORT = Number(process.env.PORT || 3000);
const started = Date.now();
let requests = 0;

function send(res, status, body) {
  res.writeHead(status, { "content-type": "application/json" });
  res.end(JSON.stringify(body) + "\n");
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, "http://localhost");
  requests += 1;

  switch (url.pathname) {
    case "/":
      // Which instance answered? The container's hostname is its id.
      return send(res, 200, {
        instance: os.hostname(),
        uptime_seconds: Math.round((Date.now() - started) / 1000),
        requests,
      });

    case "/health":
      // Used by Docker's HEALTHCHECK and by Caddy's active health check.
      return send(res, 200, { status: "ok" });

    case "/crash":
      // The process exits: the container stops (slide 322).
      send(res, 200, { instance: os.hostname(), action: "crashing now" });
      return setImmediate(() => process.exit(1));

    case "/freeze":
      // The process stays alive but never answers again: a busy loop blocks Node's
      // single thread, so even /health gets no reply (slide 324).
      send(res, 200, { instance: os.hostname(), action: "freezing now" });
      return setImmediate(() => {
        for (;;) {
          /* spin forever */
        }
      });

    case "/cpu": {
      // Heavy work for a few seconds, then back to normal: slow, but not broken.
      const seconds = Math.min(Number(url.searchParams.get("seconds") || 3), 10);
      const until = Date.now() + seconds * 1000;
      let n = 0;
      while (Date.now() < until) n += Math.sqrt(n + 1);
      return send(res, 200, { instance: os.hostname(), action: `busy for ${seconds}s` });
    }

    default:
      return send(res, 404, { error: "not found" });
  }
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`instance ${os.hostname()} listening on port ${PORT}`);
});
