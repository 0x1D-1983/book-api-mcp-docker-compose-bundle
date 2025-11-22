# Service Mesh with Envoy and mTLS

This directory contains the Kubernetes configuration for a service mesh architecture using Envoy sidecars with mutual TLS (mTLS) between services.

## Architecture Overview

The service mesh implements:
- **Envoy sidecars** in each pod to handle service-to-service communication
- **mTLS encryption** for all inter-service traffic
- **Automatic traffic interception** via Envoy sidecars
- **Certificate-based authentication** between services

## Components

### Services
- **bookapi**: Main Book API service (port 5288)
- **bookapi-mcp-server**: MCP server that communicates with bookapi (port 5289)

### Envoy Sidecar Configuration
Each service pod includes an Envoy sidecar that:
- Listens on port **15001** for inbound traffic (with mTLS)
- Listens on port **15006** for outbound traffic interception
- Exposes admin interface on port **9901**

### Traffic Flow
1. **Inbound**: External services → Envoy sidecar (15001) → Application (5288/5289)
2. **Outbound**: Application → Envoy sidecar (15006) → Target service Envoy sidecar (15001) → Target application

## Setup Instructions

### 1. Generate Certificates

First, generate the mTLS certificates:

```bash
cd k8s/service-mesh
chmod +x generate-certs.sh
./generate-certs.sh
```

This will create certificates in the `certs/` directory.

### 2. Create Kubernetes Secrets

Create the secrets from the generated certificates:

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

# pgAdmin Secret
kubectl create secret generic pgadmin-mtls-cert \
  --from-file=tls.crt=./certs/pgadmin.crt \
  --from-file=tls.key=./certs/pgadmin.key \
  --from-file=ca.crt=./certs/ca.crt

# TimescaleDB Secret
kubectl create secret generic timescaledb-mtls-cert \
  --from-file=tls.crt=./certs/timescaledb.crt \
  --from-file=tls.key=./certs/timescaledb.key \
  --from-file=ca.crt=./certs/ca.crt

# Edge Envoy Secret
kubectl create secret generic envoy-mtls-cert \
  --from-file=tls.crt=./certs/envoy.crt \
  --from-file=tls.key=./certs/envoy.key \
  --from-file=ca.crt=./certs/ca.crt
```

### 3. Apply Service Mesh Configuration

Apply all service mesh resources:

```bash
kubectl apply -k k8s/service-mesh/
```

Or apply individually:

```bash
# Apply certificates
kubectl apply -f k8s/service-mesh/cert-manager.yaml

# Apply Envoy configs
kubectl apply -f k8s/service-mesh/configmap-bookapi-envoy.yaml
kubectl apply -f k8s/service-mesh/configmap-bookapi-mcp-server-envoy.yaml

# Apply deployments
kubectl apply -f k8s/service-mesh/bookapi-deployment.yaml
kubectl apply -f k8s/service-mesh/bookapi-mcp-server-deployment.yaml

# Apply services
kubectl apply -f k8s/service-mesh/bookapi-service.yaml
kubectl apply -f k8s/service-mesh/bookapi-mcp-server-service.yaml
```

## Configuration Details

### Envoy Sidecar Ports
- **15001**: Inbound listener (receives mTLS traffic from other services)
- **15006**: Outbound listener (intercepts traffic from local application)
- **9901**: Admin interface

### Service Ports
- Services expose both:
  - Port **15001**: mTLS endpoint (via Envoy sidecar)
  - Port **5288/5289**: Direct application access (for debugging)

### mTLS Configuration
- **Client certificates required**: Yes (`require_client_certificate: true`)
- **Certificate validation**: Validates against CA and checks SANs
- **Subject Alternative Names (SANs)**: Includes service name and FQDN

## Verification

### Check Envoy Sidecars

Verify Envoy sidecars are running:

```bash
kubectl get pods -l app=bookapi
kubectl get pods -l app=bookapi-mcp-server
```

Each pod should have 2 containers: the application and the envoy sidecar.

### Check Envoy Admin Interface

Port-forward to access Envoy admin:

```bash
# For bookapi
kubectl port-forward <bookapi-pod-name> 9901:9901

# Access http://localhost:9901/stats to see Envoy metrics
```

### Test mTLS Connection

Test that services can communicate via mTLS:

```bash
# Exec into bookapi-mcp-server pod
kubectl exec -it <bookapi-mcp-server-pod-name> -c bookapi-mcp-server -- sh

# Test connection (should use Envoy sidecar)
curl http://127.0.0.1:15006/books
```

### View Envoy Logs

```bash
# View Envoy sidecar logs
kubectl logs <pod-name> -c envoy
```

## Troubleshooting

### Certificate Issues
- Ensure certificates are valid and not expired
- Check SANs match service names
- Verify CA certificate is trusted

### Connection Issues
- Check Envoy sidecar is running: `kubectl get pods -c envoy`
- Verify service endpoints: `kubectl get endpoints`
- Check Envoy logs for errors

### Configuration Issues
- Validate Envoy config: `kubectl exec <pod> -c envoy -- envoy --mode validate -c /etc/envoy/envoy.yaml`
- Check ConfigMap: `kubectl get configmap bookapi-envoy-config -o yaml`

## Migration from Non-Mesh Architecture

To migrate from the existing architecture:

1. **Backup current deployments**:
   ```bash
   kubectl get deployment bookapi -o yaml > bookapi-backup.yaml
   kubectl get deployment bookapi-mcp-server -o yaml > bookapi-mcp-server-backup.yaml
   ```

2. **Update ConfigMap** for bookapi-mcp-server to use Envoy:
   - Change `BookApi__BaseUrl` to `http://127.0.0.1:15006` (Envoy outbound port)
   - Envoy will handle routing to bookapi with mTLS

3. **Apply new deployments** (they will replace existing ones)

4. **Verify services are communicating** via mTLS

## Security Considerations

- **Certificate rotation**: Set up automated certificate rotation (consider using cert-manager)
- **Network policies**: Implement Kubernetes NetworkPolicies to restrict traffic
- **Secret management**: Use proper secret management (e.g., sealed-secrets, external-secrets)
- **Certificate storage**: Never commit private keys to version control

## Future Enhancements

- [ ] Integrate with cert-manager for automatic certificate management
- [ ] Add service mesh observability (metrics, tracing, logging)
- [ ] Implement traffic policies (rate limiting, circuit breakers)
- [ ] Add service mesh dashboard
- [ ] Implement zero-trust networking policies

