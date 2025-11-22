#!/bin/bash
# Script to fix all Envoy sidecar and edge Envoy certificate issues
# This replaces placeholder certificates with real ones and ensures all secrets use the same CA

set -e

CERT_DIR="./certs"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Fixing All Service Mesh Certificates ==="
echo ""

# Check if certificates exist
if [ ! -d "$CERT_DIR" ]; then
  echo "ERROR: Certificate directory not found: $CERT_DIR"
  echo "Generating certificates..."
  chmod +x generate-certs.sh
  ./generate-certs.sh
fi

# Verify required certificates exist
REQUIRED_CERTS=("ca.crt" "bookapi.crt" "bookapi.key" "bookapi-mcp-server.crt" "bookapi-mcp-server.key" "pgadmin.crt" "pgadmin.key" "envoy.crt" "envoy.key")
MISSING_CERTS=()

for cert in "${REQUIRED_CERTS[@]}"; do
  if [ ! -f "$CERT_DIR/$cert" ]; then
    MISSING_CERTS+=("$cert")
  fi
done

if [ ${#MISSING_CERTS[@]} -gt 0 ]; then
  echo "ERROR: Missing required certificates: ${MISSING_CERTS[*]}"
  echo "Generating certificates..."
  chmod +x generate-certs.sh
  ./generate-certs.sh
fi

echo "✓ Certificates found"
echo ""

# Delete existing placeholder secrets
echo "Deleting placeholder secrets..."
kubectl delete secret bookapi-mtls-cert 2>/dev/null || echo "  bookapi-mtls-cert not found (will create new)"
kubectl delete secret bookapi-mcp-server-mtls-cert 2>/dev/null || echo "  bookapi-mcp-server-mtls-cert not found (will create new)"
kubectl delete secret pgadmin-mtls-cert 2>/dev/null || echo "  pgadmin-mtls-cert not found (will create new)"
kubectl delete secret envoy-mtls-cert 2>/dev/null || echo "  envoy-mtls-cert not found (will create new)"
kubectl delete secret timescaledb-mtls-cert 2>/dev/null || echo "  timescaledb-mtls-cert not found (will create new)"
echo ""

# Create/update all secrets with real certificates using the same CA
echo "Creating/updating secrets with real certificates (using same CA)..."
echo ""

# BookAPI secret
echo "Creating bookapi-mtls-cert..."
kubectl create secret generic bookapi-mtls-cert \
  --from-file=tls.crt="$CERT_DIR/bookapi.crt" \
  --from-file=tls.key="$CERT_DIR/bookapi.key" \
  --from-file=ca.crt="$CERT_DIR/ca.crt"

# BookAPI MCP Server secret
echo "Creating bookapi-mcp-server-mtls-cert..."
kubectl create secret generic bookapi-mcp-server-mtls-cert \
  --from-file=tls.crt="$CERT_DIR/bookapi-mcp-server.crt" \
  --from-file=tls.key="$CERT_DIR/bookapi-mcp-server.key" \
  --from-file=ca.crt="$CERT_DIR/ca.crt"

# pgAdmin secret
echo "Creating pgadmin-mtls-cert..."
kubectl create secret generic pgadmin-mtls-cert \
  --from-file=tls.crt="$CERT_DIR/pgadmin.crt" \
  --from-file=tls.key="$CERT_DIR/pgadmin.key" \
  --from-file=ca.crt="$CERT_DIR/ca.crt"

# Edge Envoy secret
echo "Creating envoy-mtls-cert..."
kubectl create secret generic envoy-mtls-cert \
  --from-file=tls.crt="$CERT_DIR/envoy.crt" \
  --from-file=tls.key="$CERT_DIR/envoy.key" \
  --from-file=ca.crt="$CERT_DIR/ca.crt"

# TimescaleDB secret (if exists)
if [ -f "$CERT_DIR/timescaledb.crt" ] && [ -f "$CERT_DIR/timescaledb.key" ]; then
  echo "Creating timescaledb-mtls-cert..."
  kubectl create secret generic timescaledb-mtls-cert \
    --from-file=tls.crt="$CERT_DIR/timescaledb.crt" \
    --from-file=tls.key="$CERT_DIR/timescaledb.key" \
    --from-file=ca.crt="$CERT_DIR/ca.crt"
fi

echo ""
echo "✓ All secrets created/updated with matching CA"
echo ""

# Restart pods to pick up new certificates
echo "Restarting pods to pick up new certificates..."
kubectl delete pod -l app=bookapi 2>/dev/null || echo "  No bookapi pods to delete"
kubectl delete pod -l app=bookapi-mcp-server 2>/dev/null || echo "  No bookapi-mcp-server pods to delete"
kubectl delete pod -l app=pgadmin 2>/dev/null || echo "  No pgadmin pods to delete"
kubectl delete pod -l app=envoy 2>/dev/null || echo "  No envoy pods to delete"
kubectl delete pod -l app=timescaledb 2>/dev/null || echo "  No timescaledb pods to delete"
echo ""

echo "Waiting for pods to restart..."
sleep 5

# Check pod status
echo ""
echo "Checking pod status..."
kubectl get pods -l app=bookapi 2>/dev/null || echo "No bookapi pods"
kubectl get pods -l app=bookapi-mcp-server 2>/dev/null || echo "No bookapi-mcp-server pods"
kubectl get pods -l app=pgadmin 2>/dev/null || echo "No pgadmin pods"
kubectl get pods -l app=envoy 2>/dev/null || echo "No envoy pods"
echo ""

echo "=== Fix Complete ==="
echo ""
echo "Wait a few seconds for pods to start, then check:"
echo "  kubectl get pods"
echo ""
echo "To view Envoy logs:"
echo "  kubectl logs <pod-name> -c envoy"
echo "  kubectl logs -l app=envoy"
echo ""
echo "To verify CA certificates match:"
echo "  kubectl get secret envoy-mtls-cert -o jsonpath='{.data.ca\.crt}' | base64 -d | openssl x509 -fingerprint -noout"
echo "  kubectl get secret pgadmin-mtls-cert -o jsonpath='{.data.ca\.crt}' | base64 -d | openssl x509 -fingerprint -noout"
echo ""

