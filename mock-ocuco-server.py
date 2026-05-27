#!/usr/bin/env python3
"""
Mock Ocuco Innovation API server for testing firewall connectivity
Responds to /api/v2/order_summary endpoint with 401 (auth required)
Run on backup server (192.168.50.13) to test firewall routing

Usage:
  python3 mock-ocuco-server.py          # Run on port 8090
  python3 mock-ocuco-server.py 80       # Run on port 80 (requires admin)
  python3 mock-ocuco-server.py 443      # Run on port 443 (requires admin)
"""

import json
import sys
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8090


class MockOcucoHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        timestamp = datetime.utcnow().isoformat() + 'Z'
        self.log_message(f'GET {self.path}')

        # CORS headers
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')

        # Mock Ocuco API endpoints
        if self.path == '/api/v2/order_summary':
            self.send_response(401)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            response = {
                'error': 'Unauthorized',
                'message': 'Authentication required',
                'timestamp': timestamp
            }
            self.wfile.write(json.dumps(response).encode())
            return

        # Health check endpoint
        if self.path in ['/', '/health']:
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            response = {
                'status': 'ok',
                'service': 'mock-ocuco-api',
                'timestamp': timestamp
            }
            self.wfile.write(json.dumps(response).encode())
            return

        # 404 for unknown endpoints
        self.send_response(404)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        response = {
            'error': 'Not Found',
            'path': self.path,
            'timestamp': timestamp
        }
        self.wfile.write(json.dumps(response).encode())

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization')
        self.end_headers()

    def log_message(self, format, *args):
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        print(f'[{timestamp}] {format % args}', file=sys.stderr)


if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', PORT), MockOcucoHandler)

    print('\n' + '=' * 60)
    print('Mock Ocuco Innovation API Server')
    print('=' * 60)
    print(f'\nListening on port {PORT}')
    print(f'Server: 192.168.50.13:{PORT}')
    print('\nMock API Endpoints:')
    print('  GET /health — Health check')
    print('  GET /api/v2/order_summary — Returns 401 (auth required)')
    print('  Any other path — Returns 404')
    print('\nLocal testing:')
    print(f'  curl http://192.168.50.13:{PORT}/health')
    print(f'  curl http://192.168.50.13:{PORT}/api/v2/order_summary')
    print('\nExternal testing (from AWS via WAN IP 158.41.81.58):')
    print(f'  curl https://158.41.81.58:{PORT}/health')
    print(f'  curl -k https://158.41.81.58:{PORT}/api/v2/order_summary')
    print('\nPress Ctrl+C to stop server\n')

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('\n\nShutting down mock server...')
        server.shutdown()
        sys.exit(0)
