# Migration Guide: Non-Mesh to Service Mesh Architecture

This guide explains how to migrate from the current non-mesh architecture to the service mesh with mTLS.

## Architecture Changes

### Before (Non-Mesh)
```
bookapi-mcp-server → (HTTP) → bookapi
```

### After (Service Mesh)
```
bookapi-mcp-server → Envoy Sidecar (15006) → (mTLS) → bookapi Envoy Sidecar (15001) → bookapi
```

## Step-by-Step Migration

### 1. Generate Certificates

```bash
cd k8s/service-mesh
./generate-certs.sh
```

### 2. Create Kubernetes Secrets

```bash
# CA Secret
kubectl create secret generic service-mesh-ca \
  --from-file=ca.crt=./certs/ca.crt \
  --from-file=ca.key=./certs/ca.key

# BookAPI Secret
kubectl create secret generic bookapi-mtls-cert \
  --from-file=tls.crt=./certs/bookapi.crt \
  --from-file=tls.key=./certs/bookapi.key \
  --from-file=ca.crt=./certs/ca.crt

# BookAPI MCP Server Secret
kubectl create secret generic bookapi-mcp-server-mtls-cert \
  --from-file=tls.crt=./certs/bookapi-mcp-server.crt \
  --from-file=tls.key=./certs/bookapi-mcp-server.key \
  --from-file=ca.crt=./certs/ca.crt
```

### 3. Apply Envoy Configurations

```bash
kubectl apply -f k8s/service-mesh/configmap-bookapi-envoy.yaml
kubectl apply -f k8s/service-mesh/configmap-bookapi-mcp-server-envoy.yaml
```

### 4. Update ConfigMap for bookapi-mcp-server

The deployment will automatically update the `BookApi__BaseUrl` environment variable to use the Envoy sidecar (`http://127.0.0.1:15006`).

If you need to update the ConfigMap manually:

```bash
kubectl patch configmap bookapi-mcp-server-config --type merge -p '{"data":{"BookApi__BaseUrl":"http://127.0.0.1:15006"}}'
```

### 5. Apply New Deployments

```bash
# Backup existing deployments (optional)
kubectl get deployment bookapi -o yaml > bookapi-backup.yaml
kubectl get deployment bookapi-mcp-server -o yaml > bookapi-mcp-server-backup.yaml

# Apply new deployments with Envoy sidecars
kubectl apply -f k8s/service-mesh/bookapi-deployment.yaml
kubectl apply -f k8s/service-mesh/bookapi-mcp-server-deployment.yaml
```

### 6. Update Services

```bash
kubectl apply -f k8s/service-mesh/bookapi-service.yaml
kubectl apply -f k8s/service-mesh/bookapi-mcp-server-service.yaml
```

### 7. Verify Migration

#### Check Pods
```bash
# Each pod should have 2 containers (app + envoy)
kubectl get pods -l app=bookapi
kubectl get pods -l app=bookapi-mcp-server

# Check container status
kubectl describe pod <pod-name>
```

#### Test Connectivity
```bash
# Test from bookapi-mcp-server to bookapi via mTLS
kubectl exec -it <bookapi-mcp-server-pod> -c bookapi-mcp-server -- \
  curl -v http://127.0.0.1:15006/books
```

#### Check Envoy Logs
```bash
# View Envoy sidecar logs
kubectl logs <pod-name> -c envoy

# Check for mTLS handshake
kubectl logs <pod-name> -c envoy | grep -i tls
```

#### Verify mTLS
```bash
# Check Envoy stats for TLS connections
kubectl port-forward <pod-name> 9901:9901
curl http://localhost:9901/stats | grep tls
```

## Rollback Procedure

If you need to rollback to the non-mesh architecture:

```bash
# Restore original deployments
kubectl apply -f k8s/bookapi/deployment.yaml
kubectl apply -f k8s/bookapi-mcp-server/deployment.yaml

# Restore original services
kubectl apply -f k8s/bookapi/service.yaml
kubectl apply -f k8s/bookapi-mcp-server/service.yaml

# Update ConfigMap to use direct connection
kubectl patch configmap bookapi-mcp-server-config --type merge -p '{"data":{"BookApi__BaseUrl":"http://bookapi:5288"}}'
```

## Configuration Changes Summary

| Component | Before | After |
|-----------|--------|-------|
| bookapi-mcp-server → bookapi | HTTP direct | HTTP → Envoy → mTLS → Envoy → HTTP |
| bookapi-mcp-server BaseUrl | `http://bookapi:5288` | `http://127.0.0.1:15006` |
| Service Ports | 5288/5289 | 15001 (mTLS) + 5288/5289 (direct) |
| Pod Containers | 1 (app) | 2 (app + envoy) |

## Troubleshooting

### Issue: Pods not starting
- Check if secrets exist: `kubectl get secrets`
- Verify certificate format: `kubectl get secret bookapi-mtls-cert -o yaml`

### Issue: mTLS handshake failing
- Verify certificates are valid: Check SANs match service names
- Check Envoy logs for TLS errors
- Verify CA certificate is in all secrets

### Issue: Services can't communicate
- Check Envoy sidecars are running
- Verify service endpoints: `kubectl get endpoints`
- Check network policies aren't blocking traffic

### Issue: Application errors
- Verify BaseUrl is set correctly
- Check application logs for connection errors
- Ensure Envoy is routing correctly

## Performance Considerations

- **Latency**: Envoy sidecars add minimal latency (~1-2ms per hop)
- **Resource Usage**: Each sidecar uses ~64-256MB memory and ~10-500m CPU
- **Connection Pooling**: Envoy handles connection pooling automatically

## Security Benefits

- ✅ All inter-service traffic encrypted with mTLS
- ✅ Certificate-based authentication
- ✅ Service identity verification via SANs
- ✅ Defense in depth with network policies

