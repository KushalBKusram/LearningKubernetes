'use strict';
// A small, stateless web app. It keeps nothing on disk and nothing in memory
// that matters, so any number of copies can run side by side (slide 138).
// Used on days 6, 7, 9 and 10.
const express = require('express');
const fs = require('fs');
const os = require('os');
const { version } = require('./package.json');

const PORT = Number(process.env.PORT) || 3000;
const GREETING = 'Hello from the Node app';
// Set by the build automation on day 9, so the page shows which commit is running.
const COMMIT = process.env.APP_COMMIT || 'not set';
// Day 10: while this file exists, /health reports a failure.
const UNHEALTHY_FLAG = '/tmp/unhealthy';
const startedAt = new Date();

function info() {
  return {
    greeting: GREETING,
    version,
    commit: COMMIT,
    hostname: os.hostname(),
    platform: `${process.platform}/${process.arch}`,
    node: process.version,
    startedAt: startedAt.toISOString(),
  };
}

const app = express();

app.get('/', (req, res) => {
  const i = info();
  res.send(`<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Node app ${i.version}</title>
  <style>
    :root { color-scheme: light dark; }
    body { font-family: system-ui, sans-serif; line-height: 1.5; max-width: 40rem; margin: 4rem auto; padding: 0 1rem; }
    td { padding: 0.15rem 1rem 0.15rem 0; }
  </style>
</head>
<body>
  <h1>${i.greeting}</h1>
  <table>
    <tr><td>Version</td><td>${i.version}</td></tr>
    <tr><td>Commit</td><td>${i.commit}</td></tr>
    <tr><td>Container</td><td>${i.hostname}</td></tr>
    <tr><td>Platform</td><td>${i.platform}</td></tr>
    <tr><td>Node.js</td><td>${i.node}</td></tr>
    <tr><td>Started</td><td>${i.startedAt}</td></tr>
  </table>
</body>
</html>
`);
});

app.get('/api/info', (req, res) => res.json(info()));

app.get('/health', (req, res) => {
  if (fs.existsSync(UNHEALTHY_FLAG)) {
    return res.status(500).json({ status: 'unhealthy' });
  }
  res.json({ status: 'ok' });
});

const server = app.listen(PORT, () => console.log(`listening on port ${PORT}`));

// The app runs as process 1 in its container. Process 1 only reacts to the
// signals it handles itself, so without this "docker stop" would wait 10
// seconds and then kill it.
for (const signal of ['SIGTERM', 'SIGINT']) {
  process.on(signal, () => {
    console.log(`${signal} received, shutting down`);
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 3000).unref();
  });
}
