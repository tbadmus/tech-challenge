'use strict';

const express = require('express');
const os = require('os');

const app = express();
const port = Number(process.env.PORT) || 8080;

// Shown in the response so a browser screenshot proves which pod answered --
// useful for demonstrating that the ALB is load balancing across replicas.
const pod = process.env.POD_NAME || os.hostname();
const version = process.env.APP_VERSION || 'dev';

app.get('/', (req, res) => {
  res.type('html').send(`<!doctype html>
<title>Hello from EKS</title>
<style>
  body { font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
         background: #10151a; color: #e3e8ee; display: grid;
         place-items: center; min-height: 100vh; margin: 0; }
  div  { border: 1px solid #2c353f; border-radius: 6px; padding: 28px 36px; }
  h1   { margin: 0 0 14px; font-size: 1.5rem; color: #45b3aa; }
  dt   { color: #9ba6b3; font-size: .75rem; text-transform: uppercase;
         letter-spacing: .12em; margin-top: 12px; }
  dd   { margin: 2px 0 0; }
</style>
<div>
  <h1>Hello from EKS</h1>
  <dl>
    <dt>pod</dt><dd>${pod}</dd>
    <dt>version</dt><dd>${version}</dd>
    <dt>served at</dt><dd>${new Date().toISOString()}</dd>
  </dl>
</div>`);
});

// Inline SVG favicon. Without it a browser logs a 404 on every page load,
// which is noise in exactly the console output you want clean during a demo.
app.get('/favicon.ico', (req, res) => {
  res.type('image/svg+xml').send(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">' +
    '<rect width="16" height="16" rx="3" fill="#10151a"/>' +
    '<circle cx="8" cy="8" r="4" fill="none" stroke="#45b3aa" stroke-width="1.6"/>' +
    '</svg>');
});

// Separate from readiness on purpose: liveness answering means the process is
// alive, readiness answering means it should receive traffic. Pointing both at
// the same handler is how you get a deadlocked pod that is never restarted.
app.get('/healthz', (req, res) => res.status(200).json({ status: 'ok' }));
app.get('/readyz', (req, res) => res.status(200).json({ status: 'ready', pod }));

const server = app.listen(port, () => {
  console.log(JSON.stringify({ msg: 'listening', port, pod, version }));
});

// Kubernetes sends SIGTERM and waits terminationGracePeriodSeconds before
// SIGKILL. Without this the process is killed outright and in-flight requests
// are dropped mid-response.
for (const signal of ['SIGTERM', 'SIGINT']) {
  process.on(signal, () => {
    console.log(JSON.stringify({ msg: 'shutting down', signal }));
    server.close(() => process.exit(0));
  });
}
