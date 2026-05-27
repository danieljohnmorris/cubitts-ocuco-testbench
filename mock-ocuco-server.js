#!/usr/bin/env node

/**
 * Mock Ocuco Innovation API server for testing firewall connectivity
 * Responds to /api/v2/order_summary endpoint with 401 (auth required)
 * Run on backup server (192.168.50.13) to test firewall routing
 */

const http = require('http');
const https = require('https');
const fs = require('fs');

const PORT_HTTP = 80;
const PORT_HTTPS = 443;
const PORT_ALT = 8090;

// Simple HTTP request handler
const requestHandler = (req, res) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.url}`);

  // CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle OPTIONS (preflight)
  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }

  // Mock Ocuco API endpoints
  if (req.url === '/api/v2/order_summary') {
    res.writeHead(401, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      error: 'Unauthorized',
      message: 'Authentication required',
      timestamp: new Date().toISOString()
    }));
    return;
  }

  // Health check endpoint
  if (req.url === '/health' || req.url === '/') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'ok',
      service: 'mock-ocuco-api',
      timestamp: new Date().toISOString()
    }));
    return;
  }

  // 404 for unknown endpoints
  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({
    error: 'Not Found',
    path: req.url,
    timestamp: new Date().toISOString()
  }));
};

// Create servers
console.log('Starting Mock Ocuco Innovation API Server...\n');

// HTTP server (port 80 and 8090)
const httpServer = http.createServer(requestHandler);
httpServer.listen(PORT_ALT, '0.0.0.0', () => {
  console.log(`✓ HTTP server listening on port ${PORT_ALT}`);
});

httpServer.on('error', (err) => {
  if (err.code === 'EACCES') {
    console.error(`✗ Port ${PORT_ALT} requires elevated privileges. Try running with sudo.`);
  } else {
    console.error(`✗ HTTP server error:`, err.message);
  }
});

// Try HTTP on port 80 (requires sudo on Unix-like systems)
const httpServer80 = http.createServer(requestHandler);
httpServer80.listen(PORT_HTTP, '0.0.0.0', () => {
  console.log(`✓ HTTP server listening on port ${PORT_HTTP}`);
}).on('error', (err) => {
  if (err.code === 'EACCES') {
    console.log(`⚠ Port ${PORT_HTTP} requires elevated privileges (run with sudo/admin)`);
  }
});

// HTTPS server (port 443) - with self-signed cert warning
console.log('\nMock API Endpoints:');
console.log('  GET /health — Health check');
console.log('  GET /api/v2/order_summary — Returns 401 (auth required)');
console.log('  Any other path — Returns 404\n');

console.log('Testing:');
console.log(`  curl http://192.168.50.13:8090/health`);
console.log(`  curl http://192.168.50.13:8090/api/v2/order_summary\n`);

console.log('External testing (from AWS):');
console.log(`  curl https://158.41.81.58:8090/health`);
console.log(`  curl -k https://158.41.81.58:8090/api/v2/order_summary\n`);

process.on('SIGINT', () => {
  console.log('\nShutting down mock server...');
  httpServer.close();
  httpServer80.close();
  process.exit(0);
});
