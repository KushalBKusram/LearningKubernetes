// The TypeScript version of the day 6 app. Browsers and Node.js do not run
// TypeScript directly: "tsc" turns src/server.ts into dist/server.js. That compile
// step needs the TypeScript compiler, which the running app never needs again.
import express from 'express';
import fs from 'node:fs';
import os from 'node:os';

const PORT = Number(process.env.PORT) || 3000;
const UNHEALTHY_FLAG = '/tmp/unhealthy'; // while this file exists, /health fails

const app = express();

app.get('/', (_req, res) => {
  res.send('<h1>Hello from the TypeScript app</h1>');
});

app.get('/api/info', (_req, res) => {
  res.json({
    greeting: 'Hello from the TypeScript app',
    version: '2.0.0',
    hostname: os.hostname(),
    node: process.version,
    platform: `${process.platform}/${process.arch}`,
  });
});

app.get('/health', (_req, res) => {
  if (fs.existsSync(UNHEALTHY_FLAG)) {
    res.status(500).json({ status: 'unhealthy' });
    return;
  }
  res.json({ status: 'ok' });
});

const server = app.listen(PORT, () => console.log(`listening on port ${PORT}`));

for (const signal of ['SIGTERM', 'SIGINT'] as const) {
  process.on(signal, () => {
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 3000).unref();
  });
}
