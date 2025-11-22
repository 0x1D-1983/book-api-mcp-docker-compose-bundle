#!/bin/bash
# Script to tear down the service mesh
# This removes all service mesh resources: deployments, services, ConfigMaps, and optionally secrets

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Parse command line arguments
DELETE_SECRETS=false
DELETE_CERTS=false
FORCE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --delete-secrets)
      DELETE_SECRETS=true
      shift
      ;;
    --delete-certs)
      DELETE_CERTS=true
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Tears down the service mesh by removing all deployments, services, and ConfigMaps."
      echo ""
      echo "Options:"
      echo "  --delete-secrets    Also delete mTLS certificate secrets"
      echo "  --delete-certs      Also delete local certificate files"
      echo "  --force             Skip confirmation prompts"
      echo "  -h, --help          Show this help message"
      echo ""
      echo "Examples:"
      echo "  $0                                    # Remove deployments, services, ConfigMaps"
      echo "  $0 --delete-secrets                   # Also remove secrets"
      echo "  $0 --delete-secrets --delete-certs   # Remove everything including local certs"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use -h or --help for usage information"
      exit 1
      ;;
  esac
done

echo "=== Service Mesh Teardown ==="
echo ""

# Confirm deletion unless --force is used
if [ "$FORCE" != "true" ]; then
  echo "This will delete the following resources:"
  echo "  - All service mesh deployments (bookapi, bookapi-mcp-server, pgadmin, timescaledb, envoy)"
  echo "  - All service mesh services"
  echo "  - All Envoy ConfigMaps"
  if [ "$DELETE_SECRETS" = "true" ]; then
    echo "  - All mTLS certificate secrets"
  fi
  if [ "$DELETE_CERTS" = "true" ]; then
    echo "  - Local certificate files in certs/ directory"
  fi
  echo ""
  read -p "Are you sure you want to continue? (yes/no): " -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Teardown cancelled."
    exit 0
  fi
fi

# Delete deployments
echo "Deleting deployments..."
kubectl delete deployment bookapi 2>/dev/null && echo "  ✓ bookapi deployment deleted" || echo "  - bookapi deployment not found"
kubectl delete deployment bookapi-mcp-server 2>/dev/null && echo "  ✓ bookapi-mcp-server deployment deleted" || echo "  - bookapi-mcp-server deployment not found"
kubectl delete deployment pgadmin 2>/dev/null && echo "  ✓ pgadmin deployment deleted" || echo "  - pgadmin deployment not found"
kubectl delete deployment timescaledb 2>/dev/null && echo "  ✓ timescaledb deployment deleted" || echo "  - timescaledb deployment not found"
kubectl delete deployment envoy 2>/dev/null && echo "  ✓ envoy (edge) deployment deleted" || echo "  - envoy deployment not found"
echo ""

# Delete services
echo "Deleting services..."
kubectl delete service bookapi 2>/dev/null && echo "  ✓ bookapi service deleted" || echo "  - bookapi service not found"
kubectl delete service bookapi-mcp-server 2>/dev/null && echo "  ✓ bookapi-mcp-server service deleted" || echo "  - bookapi-mcp-server service not found"
kubectl delete service pgadmin 2>/dev/null && echo "  ✓ pgadmin service deleted" || echo "  - pgadmin service not found"
kubectl delete service timescaledb 2>/dev/null && echo "  ✓ timescaledb service deleted" || echo "  - timescaledb service not found"
# Note: envoy service might not exist if it's only accessed via port-forward
kubectl delete service envoy 2>/dev/null && echo "  ✓ envoy service deleted" || echo "  - envoy service not found (may not exist)"
echo ""

# Delete ConfigMaps
echo "Deleting ConfigMaps..."
kubectl delete configmap bookapi-envoy-config 2>/dev/null && echo "  ✓ bookapi-envoy-config deleted" || echo "  - bookapi-envoy-config not found"
kubectl delete configmap bookapi-mcp-server-envoy-config 2>/dev/null && echo "  ✓ bookapi-mcp-server-envoy-config deleted" || echo "  - bookapi-mcp-server-envoy-config not found"
kubectl delete configmap pgadmin-envoy-config 2>/dev/null && echo "  ✓ pgadmin-envoy-config deleted" || echo "  - pgadmin-envoy-config not found"
kubectl delete configmap timescaledb-envoy-config 2>/dev/null && echo "  ✓ timescaledb-envoy-config deleted" || echo "  - timescaledb-envoy-config not found"
kubectl delete configmap envoy-conf 2>/dev/null && echo "  ✓ envoy-conf (edge) deleted" || echo "  - envoy-conf not found"
echo ""

# Delete secrets if requested
if [ "$DELETE_SECRETS" = "true" ]; then
  echo "Deleting mTLS certificate secrets..."
  kubectl delete secret bookapi-mtls-cert 2>/dev/null && echo "  ✓ bookapi-mtls-cert deleted" || echo "  - bookapi-mtls-cert not found"
  kubectl delete secret bookapi-mcp-server-mtls-cert 2>/dev/null && echo "  ✓ bookapi-mcp-server-mtls-cert deleted" || echo "  - bookapi-mcp-server-mtls-cert not found"
  kubectl delete secret pgadmin-mtls-cert 2>/dev/null && echo "  ✓ pgadmin-mtls-cert deleted" || echo "  - pgadmin-mtls-cert not found"
  kubectl delete secret timescaledb-mtls-cert 2>/dev/null && echo "  ✓ timescaledb-mtls-cert deleted" || echo "  - timescaledb-mtls-cert not found"
  kubectl delete secret envoy-mtls-cert 2>/dev/null && echo "  ✓ envoy-mtls-cert deleted" || echo "  - envoy-mtls-cert not found"
  kubectl delete secret service-mesh-ca 2>/dev/null && echo "  ✓ service-mesh-ca deleted" || echo "  - service-mesh-ca not found"
  echo ""
fi

# Delete local certificate files if requested
if [ "$DELETE_CERTS" = "true" ]; then
  echo "Deleting local certificate files..."
  if [ -d "./certs" ]; then
    rm -f ./certs/*.crt ./certs/*.key ./certs/*.csr ./certs/*.conf ./certs/*.srl 2>/dev/null
    echo "  ✓ Certificate files deleted from certs/ directory"
    # Optionally remove the directory if empty
    rmdir ./certs 2>/dev/null && echo "  ✓ certs/ directory removed" || echo "  - certs/ directory kept (may contain other files)"
  else
    echo "  - certs/ directory not found"
  fi
  echo ""
fi

# Wait for pods to terminate
echo "Waiting for pods to terminate..."
sleep 3

# Check if any service mesh pods are still running
REMAINING_PODS=$(kubectl get pods -l 'app in (bookapi,bookapi-mcp-server,pgadmin,timescaledb,envoy)' 2>/dev/null | grep -v NAME | wc -l | tr -d ' ')
if [ "$REMAINING_PODS" -gt 0 ]; then
  echo ""
  echo "⚠ Warning: $REMAINING_PODS pod(s) still running. They may be terminating or from other deployments."
  echo "  Run 'kubectl get pods' to check status."
else
  echo "  ✓ All service mesh pods terminated"
fi

echo ""
echo "=== Teardown Complete ==="
echo ""
echo "Service mesh resources have been removed."
if [ "$DELETE_SECRETS" != "true" ]; then
  echo ""
  echo "Note: Certificate secrets were NOT deleted. To delete them, run:"
  echo "  $0 --delete-secrets"
fi
if [ "$DELETE_CERTS" != "true" ]; then
  echo ""
  echo "Note: Local certificate files were NOT deleted. To delete them, run:"
  echo "  $0 --delete-certs"
fi
echo ""
echo "To redeploy the service mesh, run:"
echo "  kubectl apply -k k8s/service-mesh/"
echo ""

