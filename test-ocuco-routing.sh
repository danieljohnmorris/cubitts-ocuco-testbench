#!/bin/bash

# Test Ocuco Innovation API connectivity through firewall
# Tests routing from WAN IP to internal Ocuco server

set -e

WAN_IP="158.41.81.58"
INTERNAL_IP="192.168.50.13"
PORTS=(80 443 8090)

echo "=== Ocuco Innovation API Routing Test ==="
echo "WAN IP: $WAN_IP"
echo "Internal IP: $INTERNAL_IP"
echo "Testing ports: ${PORTS[@]}"
echo ""

# Test 1: Local connectivity to internal IP (no firewall)
echo "Test 1: Direct connectivity to internal IP (192.168.50.13)"
echo "---"
for port in "${PORTS[@]}"; do
  echo -n "Port $port: "
  if timeout 3 bash -c "echo >/dev/tcp/$INTERNAL_IP/$port" 2>/dev/null; then
    echo "✓ OPEN"
  else
    echo "✗ CLOSED/TIMEOUT"
  fi
done
echo ""

# Test 2: External connectivity through WAN IP (through firewall)
echo "Test 2: Connectivity through firewall (via WAN IP 158.41.81.58)"
echo "---"
for port in "${PORTS[@]}"; do
  echo -n "Port $port: "
  if timeout 3 bash -c "echo >/dev/tcp/$WAN_IP/$port" 2>/dev/null; then
    echo "✓ OPEN (firewall routing working)"
  else
    echo "✗ CLOSED/TIMEOUT (check firewall rules)"
  fi
done
echo ""

# Test 3: HTTP/HTTPS endpoint test
echo "Test 3: API endpoint test (HTTPS on port 443)"
echo "---"
echo -n "Testing https://$WAN_IP/api/v2/order_summary: "
response=$(curl -k -s -w "%{http_code}" -o /dev/null https://$WAN_IP/api/v2/order_summary 2>/dev/null || echo "000")
if [ "$response" = "000" ]; then
  echo "✗ TIMEOUT or connection refused"
elif [ "$response" = "401" ] || [ "$response" = "403" ]; then
  echo "✓ API responding (HTTP $response - auth required, as expected)"
elif [ "$response" = "200" ]; then
  echo "✓ API responding (HTTP 200 - OK)"
else
  echo "? API responded with HTTP $response"
fi
echo ""

# Test 4: Test from internal server perspective
echo "Test 4: Testing from CUBITTS-APP01 (internal)"
echo "---"
echo "To test from the internal server directly:"
echo ""
echo "  # Test port 80"
echo "  curl -v http://192.168.50.13/api/v2/order_summary"
echo ""
echo "  # Test port 443"
echo "  curl -k -v https://192.168.50.13/api/v2/order_summary"
echo ""

# Summary
echo "=== Test Summary ==="
echo "If Test 1 passes: Ocuco API is running locally"
echo "If Test 2 passes: Firewall routing is working"
echo "If Test 3 shows 401/403: API is reachable but needs authentication"
echo ""
echo "Next steps:"
echo "1. Confirm which port Ocuco is listening on (80, 443, or 8090)"
echo "2. Report results to Workplace Connect"
echo "3. Run actual authentication test with API credentials"
