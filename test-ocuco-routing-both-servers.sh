#!/bin/bash

# Test Ocuco Innovation API connectivity through firewall
# Tests routing from WAN IP to both possible internal servers
# 192.168.50.10 = Live server (old office)
# 192.168.50.13 = Backup server (new office)

set -e

WAN_IP="158.41.81.58"
LIVE_SERVER="192.168.50.10"
BACKUP_SERVER="192.168.50.13"
PORTS=(80 443 8090)

echo "=== Ocuco Innovation API Routing Test (Both Servers) ==="
echo "WAN IP: $WAN_IP"
echo "Live Server (old office): $LIVE_SERVER"
echo "Backup Server (new office): $BACKUP_SERVER"
echo "Testing ports: ${PORTS[@]}"
echo ""

# Test 1: Direct connectivity to LIVE SERVER
echo "Test 1: Direct connectivity to LIVE SERVER ($LIVE_SERVER)"
echo "---"
for port in "${PORTS[@]}"; do
  echo -n "Port $port: "
  if timeout 3 bash -c "echo >/dev/tcp/$LIVE_SERVER/$port" 2>/dev/null; then
    echo "✓ OPEN"
  else
    echo "✗ CLOSED/TIMEOUT"
  fi
done
echo ""

# Test 2: Direct connectivity to BACKUP SERVER
echo "Test 2: Direct connectivity to BACKUP SERVER ($BACKUP_SERVER)"
echo "---"
for port in "${PORTS[@]}"; do
  echo -n "Port $port: "
  if timeout 3 bash -c "echo >/dev/tcp/$BACKUP_SERVER/$port" 2>/dev/null; then
    echo "✓ OPEN"
  else
    echo "✗ CLOSED/TIMEOUT"
  fi
done
echo ""

# Test 3: External connectivity through WAN IP (through firewall)
echo "Test 3: External connectivity through firewall (via WAN IP $WAN_IP)"
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

# Test 4: HTTP/HTTPS endpoint test on both servers
echo "Test 4: API endpoint test via HTTPS"
echo "---"
echo "Testing LIVE SERVER ($LIVE_SERVER):"
echo -n "  https://$LIVE_SERVER/api/v2/order_summary: "
response=$(curl -k -s -w "%{http_code}" -o /dev/null "https://$LIVE_SERVER/api/v2/order_summary" 2>/dev/null || echo "000")
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
echo "Testing BACKUP SERVER ($BACKUP_SERVER):"
echo -n "  https://$BACKUP_SERVER/api/v2/order_summary: "
response=$(curl -k -s -w "%{http_code}" -o /dev/null "https://$BACKUP_SERVER/api/v2/order_summary" 2>/dev/null || echo "000")
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

# Test 5: External endpoint test through WAN IP
echo "Test 5: External API endpoint test (via WAN IP)"
echo "---"
echo -n "Testing https://$WAN_IP/api/v2/order_summary: "
response=$(curl -k -s -w "%{http_code}" -o /dev/null "https://$WAN_IP/api/v2/order_summary" 2>/dev/null || echo "000")
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

# Summary
echo "=== Test Summary ==="
echo "Test 1 & 2 show which server(s) have Ocuco running"
echo "Test 3 confirms firewall port routing"
echo "Tests 4 & 5 confirm API endpoint accessibility"
echo ""
echo "IMPORTANT: Confirm with Workplace Connect whether:"
echo "  - Firewall rules should point to LIVE SERVER ($LIVE_SERVER) or BACKUP SERVER ($BACKUP_SERVER)"
echo "  - Which port Ocuco is listening on (80, 443, or 8090)"
