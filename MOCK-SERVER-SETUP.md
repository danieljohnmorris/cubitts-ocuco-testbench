# Mock Ocuco Innovation API Server

A lightweight mock server to test firewall connectivity while waiting for clarification on which server should host the real Ocuco API.

## Purpose

- Test that firewall rules route traffic to **192.168.50.13** (backup server in new office where you are)
- Validate external connectivity through WAN IP **158.41.81.58**
- Confirm the integration path works before Ocuco is actually installed

## Setup on Windows (CUBITTS-HVH01)

### Option 1: Python (Recommended for Windows)

```powershell
# Check if Python is installed
python --version

# Run the mock server on port 8090
python mock-ocuco-server.py

# Or run on port 80 (requires Admin/elevated prompt)
python mock-ocuco-server.py 80
```

### Option 2: Node.js

```powershell
# Check if Node.js is installed
node --version

# Run the mock server
node mock-ocuco-server.js
```

### Option 3: Run as Admin for Port 80/443

If testing on port 80 or 443:
1. Open PowerShell as Administrator
2. Run: `python mock-ocuco-server.py 80`
3. Keep the window open while testing

## Testing from Backup Server (Local)

Once the mock server is running:

```bash
# Test health endpoint
curl http://192.168.50.13:8090/health

# Test API endpoint (should return 401 - auth required)
curl http://192.168.50.13:8090/api/v2/order_summary
```

Expected response for `/api/v2/order_summary`:
```json
{
  "error": "Unauthorized",
  "message": "Authentication required",
  "timestamp": "2026-05-27T11:35:14.123Z"
}
```

## Testing from AWS (External via WAN IP)

From your AWS environment or any external network:

```bash
# Test through WAN IP
curl https://158.41.81.58:8090/health

# Test API endpoint
curl -k https://158.41.81.58:8090/api/v2/order_summary
```

The `-k` flag ignores SSL certificate warnings (expected for mock server).

## What This Tests

✓ **Firewall rules are routing to 192.168.50.13** — If external requests reach the mock server
✓ **Port forwarding is configured** — Traffic on WAN IP 158.41.81.58 reaches the backup server
✓ **API endpoint path is correct** — `/api/v2/order_summary` is accessible
✓ **Integration chain works** — End-to-end path from AWS → firewall → backup server

## Mock Server Responses

| Endpoint | Method | Status | Response |
|----------|--------|--------|----------|
| `/health` | GET | 200 | `{status: "ok"}` |
| `/api/v2/order_summary` | GET | 401 | `{error: "Unauthorized"}` |
| Any other path | GET | 404 | `{error: "Not Found"}` |
| All | OPTIONS | 200 | CORS headers |

## Cleanup

When done testing:
- Stop the mock server (Ctrl+C in the terminal)
- Wait for Ben's clarification on the real Ocuco setup
- Real Ocuco will replace the mock server once installed

## Troubleshooting

**Port already in use:**
```powershell
# Find what's using port 8090
netstat -ano | findstr :8090

# Kill process (replace PID)
taskkill /PID <PID> /F
```

**Permission denied (port 80/443):**
- Run PowerShell as Administrator
- Use port 8090 instead (no elevated privileges needed)

**Can't connect from AWS:**
- Confirm firewall rules point to 192.168.50.13
- Confirm mock server is running (`python mock-ocuco-server.py`)
- Check firewall logs to see if traffic is being blocked
- Verify you're using the correct WAN IP (158.41.81.58)
