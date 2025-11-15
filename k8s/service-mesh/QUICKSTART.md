# Service Mesh Quick Start

Quick reference for deploying the service mesh with mTLS.

## Prerequisites

- Kubernetes cluster
- `kubectl` configured
- `openssl` installed (for certificate generation)

## Quick Deploy

```bash
# 1. Generate certificates
cd k8s/service-mesh
./generate-certs.sh

# 2. Create secrets
kubectl create secret generic service-mesh-ca \
  --from-file=ca.crt=./certs/ca.crt \
  --from-file=ca.key=./certs/ca.key

kubectl create secret generic bookapi-mtls-cert \
  --from-file=tls.crt=./certs/bookapi.crt \
  --from-file=tls.key=./certs/bookapi.key \
  --from-file=ca.crt=./certs/ca.crt

kubectl create secret generic bookapi-mcp-server-mtls-cert \
  --from-file=tls.crt=./certs/bookapi-mcp-server.crt \
  --from-file=tls.key=./certs/bookapi-mcp-server.key \
  --from-file=ca.crt=./certs/ca.crt

# 3. Deploy everything
kubectl apply -k .
```

## Verify

```bash
# Check pods (should have 2 containers each)
kubectl get pods

# Check Envoy sidecars
kubectl get pods -o jsonpath='{.items[*].spec.containers[*].name}'

# Test connectivity
kubectl exec -it <bookapi-mcp-server-pod> -c bookapi-mcp-server -- \
  curl http://127.0.0.1:15006/books
```

## Port Reference

| Service | Application Port | Envoy Inbound | Envoy Outbound | Envoy Admin |
|---------|-----------------|---------------|----------------|-------------|
| bookapi | 5288 | 15001 | 15006 | 9901 |
| bookapi-mcp-server | 5289 | 15001 | 15006 | 9901 |

## Common Commands

```bash
# View Envoy logs
kubectl logs <pod-name> -c envoy

# Access Envoy admin
kubectl port-forward <pod-name> 9901:9901
# Then visit http://localhost:9901

# Check Envoy stats
kubectl port-forward <pod-name> 9901:9901
curl http://localhost:9901/stats

# Validate Envoy config
kubectl exec <pod-name> -c envoy -- \
  envoy --mode validate -c /etc/envoy/envoy.yaml
```

