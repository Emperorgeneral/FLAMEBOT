/* Minimal static server with security headers for Railway.

   Why: Static hosts like Cloudflare Pages/Netlify can read `_headers`, but Railway
   running `serve` won't apply that file. This server serves the same files and
   adds real HTTP security headers.
*/

const http = require('http');
const fs = require('fs');
const path = require('path');
const url = require('url');

const ROOT = __dirname;
const PORT = Number(process.env.PORT || 3000);

const CANONICAL_HOST = 'www.flamebotapp.com';

const CSP = "default-src 'self'; base-uri 'self'; object-src 'none'; frame-ancestors 'none'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; connect-src 'none'; form-action 'self' mailto:; upgrade-insecure-requests";

function setSecurityHeaders(req, res) {
  // NOTE: We intentionally keep headers aligned with the meta CSP in the HTML.
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  res.setHeader('Cross-Origin-Resource-Policy', 'same-origin');
  res.setHeader('Content-Security-Policy', CSP);

  // Only send HSTS when we are effectively on HTTPS.
  // Cloudflare/Railway commonly set X-Forwarded-Proto.
  const forwardedProto = String(req.headers['x-forwarded-proto'] || '').toLowerCase();
  if (forwardedProto === 'https') {
    // Safer default: do not includeSubDomains/preload unless you are 100% sure
    // every subdomain will always support HTTPS.
    res.setHeader('Strict-Transport-Security', 'max-age=31536000');
  }
}

function safeJoin(root, requestPath) {
  // Prevent path traversal
  const decoded = decodeURIComponent(requestPath);
  const normalized = path.normalize(decoded).replace(/^([/\\])+/, '');
  return path.join(root, normalized);
}

function contentTypeFor(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  switch (ext) {
    case '.html': return 'text/html; charset=utf-8';
    case '.css': return 'text/css; charset=utf-8';
    case '.js': return 'application/javascript; charset=utf-8';
    case '.json': return 'application/json; charset=utf-8';
    case '.png': return 'image/png';
    case '.ico': return 'image/x-icon';
    case '.svg': return 'image/svg+xml; charset=utf-8';
    case '.txt': return 'text/plain; charset=utf-8';
    default: return 'application/octet-stream';
  }
}

function serveFile(req, res, filePath) {
  fs.stat(filePath, (err, stat) => {
    if (err || !stat.isFile()) {
      res.statusCode = 404;
      res.setHeader('Content-Type', 'text/plain; charset=utf-8');
      res.end('Not found');
      return;
    }

    res.statusCode = 200;
    res.setHeader('Content-Type', contentTypeFor(filePath));

    // Cache static assets lightly; keep HTML uncached to allow fast updates.
    if (filePath.endsWith('.html')) {
      res.setHeader('Cache-Control', 'no-cache');
    } else {
      res.setHeader('Cache-Control', 'public, max-age=3600');
    }

    const stream = fs.createReadStream(filePath);
    stream.on('error', () => {
      res.statusCode = 500;
      res.setHeader('Content-Type', 'text/plain; charset=utf-8');
      res.end('Server error');
    });
    stream.pipe(res);
  });
}

const server = http.createServer((req, res) => {
  const hostHeader = String(req.headers.host || '').toLowerCase();
  const host = hostHeader.split(':')[0];
  const forwardedProto = String(req.headers['x-forwarded-proto'] || '').toLowerCase();
  const isLocalHost = host === 'localhost' || host === '127.0.0.1';

  setSecurityHeaders(req, res);

  // Canonicalize to https://www.flamebotapp.com in production.
  // This avoids duplicate-content URLs across:
  // - flamebotapp.com
  // - flamebot-production.up.railway.app
  // and ensures consistent HTTPS.
  if (!isLocalHost) {
    const needsCanonicalHost = host && host !== CANONICAL_HOST;
    const needsHttps = forwardedProto && forwardedProto !== 'https';

    if (needsCanonicalHost || needsHttps) {
      const location = `https://${CANONICAL_HOST}${req.url || '/'}`;
      res.statusCode = 308;
      res.setHeader('Location', location);
      res.setHeader('Content-Type', 'text/plain; charset=utf-8');
      res.end(`Redirecting to ${location}`);
      return;
    }
  }

  const parsed = url.parse(req.url || '/');
  const pathname = String(parsed.pathname || '/');

  // Map request path -> filesystem path.
  // - /download/ -> /download/index.html
  // - / -> /index.html
  let fsPath;

  if (pathname.endsWith('/')) {
    fsPath = safeJoin(ROOT, pathname + 'index.html');
  } else {
    fsPath = safeJoin(ROOT, pathname);
  }

  // If requesting a directory without trailing slash, try to serve its index.
  fs.stat(fsPath, (err, stat) => {
    if (!err && stat.isDirectory()) {
      return serveFile(req, res, path.join(fsPath, 'index.html'));
    }

    // Fallbacks:
    // - If /something has no extension and doesn't exist as a file, try /something.html
    //   (useful for /privacy -> /privacy.html if you ever add such links)
    if (err && !path.extname(fsPath)) {
      const htmlCandidate = fsPath + '.html';
      return serveFile(req, res, htmlCandidate);
    }

    return serveFile(req, res, fsPath);
  });
});

server.listen(PORT, '0.0.0.0', () => {
  // eslint-disable-next-line no-console
  console.log(`FlameBot website server listening on :${PORT}`);
});
