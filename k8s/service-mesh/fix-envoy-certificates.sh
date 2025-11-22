#!/bin/bash
# Script to fix Envoy sidecar certificate issues
# This replaces placeholder certificates with real ones

set -e

CERT_DIR="./certs"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Fixing Envoy Sidecar Certificates ==="
echo ""

# Check if certificates exist
if [ ! -d "$CERT_DIR" ]; then
  echo "ERROR: Certificate directory not found: $CERT_DIR"
  echo "Generating certificates..."
  chmod +x generate-certs.sh
  ./generate-certs.sh
fi

# Verify required certificates exist
if [ ! -f "$CERT_DIR/ca.crt" ] || [ ! -f "$CERT_DIR/bookapi.crt" ] || [ ! -f "$CERT_DIR/bookapi.key" ]; then
  echo "ERROR: Missing required certificates. Generating..."
  chmod +x generate-certs.sh
  ./generate-certs.sh
fi

if [ ! -f "$CERT_DIR/bookapi-mcp-server.crt" ] || [ ! -f "$CERT_DIR/bookapi-mcp-server.key" ]; then
  echo "ERROR: Missing bookapi-mcp-server certificates. Generating..."
  chmod +x generate-certs.sh
  ./generate-certs.sh
fi

echo "✓ Certificates found"
echo ""

# Delete existing placeholder secrets
echo "Deleting placeholder secrets..."
kubectl delete secret bookapi-mtls-cert 2>/dev/null || echo "  bookapi-mtls-cert not found (will create new)"
kubectl delete secret bookapi-mcp-server-mtls-cert 2>/dev/null || echo "  bookapi-mcp-server-mtls-cert not found (will create new)"
echo ""

# Create new secrets with real certificates
echo "Creating secrets with real certificates..."
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

# pgAdmin secret (needed for edge Envoy to connect)
if [ -f "$CERT_DIR/pgadmin.crt" ] && [ -f "$CERT_DIR/pgadmin.key" ]; then
  echo "Updating pgadmin-mtls-cert..."
  kubectl delete secret pgadmin-mtls-cert 2>/dev/null || echo "  pgadmin-mtls-cert not found (will create new)"
  kubectl create secret generic pgadmin-mtls-cert \
    --from-file=tls.crt="$CERT_DIR/pgadmin.crt" \
    --from-file=tls.key="$CERT_DIR/pgadmin.key" \
    --from-file=ca.crt="$CERT_DIR/ca.crt"
fi

# Edge Envoy secret (needed for edge Envoy to connect to backend services)
if [ -f "$CERT_DIR/envoy.crt" ] && [ -f "$CERT_DIR/envoy.key" ]; then
  echo "Updating envoy-mtls-cert..."
  kubectl delete secret envoy-mtls-cert 2>/dev/null || echo "  envoy-mtls-cert not found (will create new)"
  kubectl create secret generic envoy-mtls-cert \
    --from-file=tls.crt="$CERT_DIR/envoy.crt" \
    --from-file=tls.key="$CERT_DIR/envoy.key" \
    --from-file=ca.crt="$CERT_DIR/ca.crt"
fi

echo ""
echo "✓ Secrets created/updated"
echo ""

# Restart pods to pick up new certificates
echo "Restarting pods to pick up new certificates..."
kubectl delete pod -l app=bookapi 2>/dev/null || echo "  No bookapi pods to delete"
kubectl delete pod -l app=bookapi-mcp-server 2>/dev/null || echo "  No bookapi-mcp-server pods to delete"
echo ""

echo "Waiting for pods to restart..."
sleep 5

# Check pod status
echo ""
echo "Checking pod status..."
kubectl get pods -l app=bookapi
kubectl get pods -l app=bookapi-mcp-server
echo ""

echo "=== Fix Complete ==="
echo ""
echo "Wait a few seconds for pods to start, then check:"
echo "  kubectl get pods -l app=bookapi"
echo "  kubectl get pods -l app=bookapi-mcp-server"
echo ""
echo "To view Envoy logs:"
echo "  kubectl logs <pod-name> -c envoy"
echo ""

