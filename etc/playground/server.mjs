import http from 'node:http';
import { createHash, randomUUID } from 'node:crypto';
import { spawn } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const sourceLimit = 64 * 1024;

export class CompileError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

export function validateSource(source) {
  // Join continued directives before examining literal include paths.
  const text = source.replace(/\\\r?\n/g, '').replace(/\/\*[\s\S]*?\*\//g, '');
  for (const match of text.matchAll(/^\s*#\s*include\s*([^\n]*)/gm)) {
    const literal = match[1].match(/^[<"]([^>"]+)[>"]/);
    if (!literal) throw new CompileError(400, 'Use literal include paths in the playground.');
    const path = literal[1].replaceAll('\\', '/');
    if (path.startsWith('/') || /^[a-z]:/i.test(path) || path.split('/').includes('..'))
      throw new CompileError(400, 'Absolute and parent include paths are unavailable.');
    if (path.split('/').at(-1) === 'process.x')
      throw new CompileError(400, 'process.x is unavailable in the browser playground.');
  }
}

export function compileInContainer(source, { image = 'x2c-playground', timeout = 20000 } = {}) {
  return new Promise((resolve, reject) => {
    const name = `x2c-playground-${randomUUID()}`;
    const child = spawn('docker', ['run', '--rm', '-i', '--name', name,
      '--network=none', '--read-only', '--user=65534:65534', '--cap-drop=ALL',
      '--security-opt=no-new-privileges', '--memory=512m', '--memory-swap=512m',
      '--cpus=1', '--pids-limit=64', '--ulimit=nofile=256:256',
      '--tmpfs=/tmp:rw,exec,nosuid,nodev,size=128m,mode=1777', image],
    { stdio: ['pipe', 'pipe', 'pipe'] });
    let output = '', errors = '', bytes = 0, failed = false;
    const stop = (error) => {
      if (failed) return;
      failed = true;
      // Killing only the docker client leaves the container running.
      const removal = spawn('docker', ['rm', '-f', name], { stdio: 'ignore' });
      removal.on('error', () => {});
      child.kill('SIGKILL');
      reject(error);
    };
    const timer = setTimeout(() => stop(new CompileError(504, 'Compilation exceeded 20 seconds.')), timeout);
    child.stdout.on('data', (data) => {
      bytes += data.length;
      if (bytes > 8 * 1024 * 1024) stop(new CompileError(422, 'Compiler result exceeds the response limit.'));
      else output += data;
    });
    child.stderr.on('data', (data) => { errors = (errors + data).slice(-16384); });
    child.stdin.on('error', () => {});
    child.on('error', () => { clearTimeout(timer); reject(new CompileError(503, 'Compiler container is unavailable.')); });
    child.on('close', (code) => {
      clearTimeout(timer);
      if (failed) return;
      if (code !== 0) return reject(new CompileError(422, errors.trim() || 'Compilation failed.'));
      try { resolve(JSON.parse(output)); }
      catch { reject(new CompileError(502, 'Compiler returned an invalid result.')); }
    });
    child.stdin.end(source);
  });
}

export function createServer({ compile = compileInContainer, origins = [], now = Date.now } = {}) {
  const clients = new Map(), cache = new Map();
  let active = 0;
  return http.createServer(async (req, res) => {
    const reply = (status, body) => {
      res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
      res.end(JSON.stringify(body));
    };
    const origin = req.headers.origin;
    if (origin && !origins.includes(origin)) return reply(403, { error: 'Origin is not allowed.' });
    if (origin) {
      res.setHeader('Access-Control-Allow-Origin', origin);
      res.setHeader('Vary', 'Origin');
    }
    if (req.url !== '/compile') return reply(404, { error: 'Not found.' });
    if (req.method === 'OPTIONS') {
      res.writeHead(204, { 'Access-Control-Allow-Methods': 'POST', 'Access-Control-Allow-Headers': 'Content-Type' });
      return res.end();
    }
    if (req.method !== 'POST') return reply(405, { error: 'Use POST /compile.' });
    const client = req.socket.remoteAddress, time = now();
    for (const [key, until] of clients) if (until <= time) clients.delete(key);
    if (clients.has(client)) {
      res.setHeader('Retry-After', '5');
      req.resume();
      return reply(429, { error: 'Wait five seconds between compilations.' });
    }
    clients.set(client, time + 5000);
    try {
      const chunks = [];
      let size = 0;
      for await (const chunk of req) {
        size += chunk.length;
        if (size > sourceLimit) {
          reply(413, { error: 'Source must not exceed 64 KB.' });
          return;
        }
        chunks.push(chunk);
      }
      const source = Buffer.concat(chunks).toString('utf8');
      validateSource(source);
      const hash = createHash('sha256').update(source).digest('hex');
      if (cache.has(hash)) return reply(200, cache.get(hash));
      if (active >= 2) return reply(503, { error: 'Compiler is busy. Try again shortly.' });
      active++;
      let result;
      try { result = await compile(source); }
      finally { active--; }
      if (cache.size >= 32) cache.delete(cache.keys().next().value);
      cache.set(hash, result);
      reply(200, result);
    } catch (error) {
      reply(error.status || 500, { error: error.status ? error.message : 'Compilation service failed.' });
    }
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const origins = (process.env.PLAYGROUND_ORIGINS || '').split(',').filter(Boolean);
  createServer({ origins, compile: source => compileInContainer(source, {
    image: process.env.PLAYGROUND_IMAGE || 'x2c-playground',
  }) }).listen(Number(process.env.PORT || 8787), process.env.HOST || '127.0.0.1');
}
