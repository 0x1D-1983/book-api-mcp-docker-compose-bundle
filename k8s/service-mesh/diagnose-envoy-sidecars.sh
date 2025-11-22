#!/bin/bash
# Diagnostic script to check why Envoy sidecars are failing

set -e

echo "=== Envoy Sidecar Diagnostic Script ==="
echo ""

# Check if pods exist
echo "1. Checking pod status..."
echo "---"
kubectl get pods -l app=bookapi -o wide 2>&1 || echo "No bookapi pods found"
echo ""
kubectl get pods -l app=bookapi-mcp-server -o wide 2>&1 || echo "No bookapi-mcp-server pods found"
echo ""

# Check Envoy container status
echo "2. Checking Envoy container status..."
echo "---"
BOOKAPI_POD=$(kubectl get pods -l app=bookapi -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
MCP_POD=$(kubectl get pods -l app=bookapi-mcp-server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$BOOKAPI_POD" ]; then
  echo "BookAPI pod: $BOOKAPI_POD"
  kubectl get pod "$BOOKAPI_POD" -o jsonpath='{.status.containerStatuses[*].name}{"\n"}' 2>&1
  kubectl get pod "$BOOKAPI_POD" -o jsonpath='{range .status.containerStatuses[*]}{.name}: {.state}{"\n"}{end}' 2>&1
  echo ""
  
  # Check Envoy logs if container exists
  if kubectl get pod "$BOOKAPI_POD" -o jsonpath='{.status.containerStatuses[*].name}' | grep -q envoy; then
    echo "Envoy logs (last 20 lines):"
    kubectl logs "$BOOKAPI_POD" -c envoy --tail=20 2>&1 || echo "Could not retrieve Envoy logs"
  else
    echo "WARNING: Envoy container not found in bookapi pod"
  fi
  echo ""
fi

if [ -n "$MCP_POD" ]; then
  echo "BookAPI MCP Server pod: $MCP_POD"
  kubectl get pod "$MCP_POD" -o jsonpath='{.status.containerStatuses[*].name}{"\n"}' 2>&1
  kubectl get pod "$MCP_POD" -o jsonpath='{range .status.containerStatuses[*]}{.name}: {.state}{"\n"}{end}' 2>&1
  echo ""
  
  # Check Envoy logs if container exists
  if kubectl get pod "$MCP_POD" -o jsonpath='{.status.containerStatuses[*].name}' | grep -q envoy; then
    echo "Envoy logs (last 20 lines):"
    kubectl logs "$MCP_POD" -c envoy --tail=20 2>&1 || echo "Could not retrieve Envoy logs"
  else
    echo "WARNING: Envoy container not found in bookapi-mcp-server pod"
  fi
  echo ""
fi

# Check if secrets exist
echo "3. Checking required secrets..."
echo "---"
kubectl get secret bookapi-mtls-cert 2>&1 || echo "ERROR: bookapi-mtls-cert secret not found"
kubectl get secret bookapi-mcp-server-mtls-cert 2>&1 || echo "ERROR: bookapi-mcp-server-mtls-cert secret not found"
echo ""

# Check if secrets contain placeholder certificates
echo "4. Checking if certificates are placeholders..."
echo "---"
if kubectl get secret bookapi-mtls-cert >/dev/null 2>&1; then
  CA_CRT=$(kubectl get secret bookapi-mtls-cert -o jsonpath='{.data.ca\.crt}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
  if echo "$CA_CRT" | grep -q "BEGIN CERTIFICATE" && ! echo "$CA_CRT" | grep -q "\.\.\."; then
    echo "✓ bookapi-mtls-cert appears to have a real certificate"
  else
    echo "✗ bookapi-mtls-cert appears to have a placeholder certificate"
    echo "  Certificate content: $(echo "$CA_CRT" | head -1)"
  fi
fi

if kubectl get secret bookapi-mcp-server-mtls-cert >/dev/null 2>&1; then
  CA_CRT=$(kubectl get secret bookapi-mcp-server-mtls-cert -o jsonpath='{.data.ca\.crt}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
  if echo "$CA_CRT" | grep -q "BEGIN CERTIFICATE" && ! echo "$CA_CRT" | grep -q "\.\.\."; then
    echo "✓ bookapi-mcp-server-mtls-cert appears to have a real certificate"
  else
    echo "✗ bookapi-mcp-server-mtls-cert appears to have a placeholder certificate"
    echo "  Certificate content: $(echo "$CA_CRT" | head -1)"
  fi
fi
echo ""

# Check if ConfigMaps exist
echo "5. Checking required ConfigMaps..."
echo "---"
kubectl get configmap bookapi-envoy-config 2>&1 || echo "ERROR: bookapi-envoy-config ConfigMap not found"
kubectl get configmap bookapi-mcp-server-envoy-config 2>&1 || echo "ERROR: bookapi-mcp-server-envoy-config ConfigMap not found"
echo ""

# Check volume mounts
echo "6. Checking volume mounts in pods..."
echo "---"
if [ -n "$BOOKAPI_POD" ]; then
  echo "BookAPI pod volumes:"
  kubectl get pod "$BOOKAPI_POD" -o jsonpath='{range .spec.volumes[*]}{.name}{": "}{.secret.secretName}{.configMap.name}{"\n"}{end}' 2>&1 || echo "Could not retrieve volume info"
  echo ""
fi

if [ -n "$MCP_POD" ]; then
  echo "BookAPI MCP Server pod volumes:"
  kubectl get pod "$MCP_POD" -o jsonpath='{range .spec.volumes[*]}{.name}{": "}{.secret.secretName}{.configMap.name}{"\n"}{end}' 2>&1 || echo "Could not retrieve volume info"
  echo ""
fi

# Check if certificates directory exists locally
echo "7. Checking local certificate files..."
echo "---"
CERT_DIR="./certs"
if [ -d "$CERT_DIR" ]; then
  echo "Certificate directory exists: $CERT_DIR"
  ls -la "$CERT_DIR"/*.crt "$CERT_DIR"/*.key 2>/dev/null | wc -l | xargs echo "Certificate files found:"
  if [ -f "$CERT_DIR/bookapi.crt" ] && [ -f "$CERT_DIR/bookapi.key" ] && [ -f "$CERT_DIR/ca.crt" ]; then
    echo "✓ Required certificates for bookapi exist locally"
  else
    echo "✗ Missing required certificates for bookapi"
  fi
  if [ -f "$CERT_DIR/bookapi-mcp-server.crt" ] && [ -f "$CERT_DIR/bookapi-mcp-server.key" ] && [ -f "$CERT_DIR/ca.crt" ]; then
    echo "✓ Required certificates for bookapi-mcp-server exist locally"
  else
    echo "✗ Missing required certificates for bookapi-mcp-server"
  fi
else
  echo "✗ Certificate directory not found: $CERT_DIR"
fi
echo ""

echo "=== Diagnostic Complete ==="
echo ""
echo "If certificates are placeholders, run:"
echo "  ./fix-envoy-certificates.sh"
echo ""
echo "Or manually:"
echo "  1. Generate certificates: ./generate-certs.sh"
echo "  2. Delete placeholder secrets: kubectl delete secret bookapi-mtls-cert bookapi-mcp-server-mtls-cert"
echo "  3. Create real secrets: (see generate-certs.sh output for commands)"
echo "  4. Restart pods: kubectl delete pod -l app=bookapi && kubectl delete pod -l app=bookapi-mcp-server"

