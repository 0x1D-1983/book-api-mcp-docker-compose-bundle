# Extended Service Mesh - All Services

This document describes the complete service mesh implementation including all services: bookapi, bookapi-mcp-server, pgAdmin, TimescaleDB, and the edge Envoy load balancer.

## Services in the Mesh

### 1. **bookapi** (Book API Service)
- **Application Port**: 5288
- **Envoy Inbound**: 15001 (mTLS)
- **Envoy Outbound HTTP**: 15006
- **Envoy Outbound TCP**: 15007 (for database connections)
- **Envoy Admin**: 9901

### 2. **bookapi-mcp-server** (MCP Server)
- **Application Port**: 5289
- **Envoy Inbound**: 15001 (mTLS)
- **Envoy Outbound HTTP**: 15006
- **Envoy Admin**: 9901
- **Connects to**: bookapi via mTLS

### 3. **pgAdmin** (Database Admin UI)
- **Application Port**: 80
- **Envoy Inbound**: 15001 (mTLS)
- **Envoy Outbound HTTP**: 15006
- **Envoy Outbound TCP**: 15007 (for database connections)
- **Envoy Admin**: 9901
- **Connects to**: timescaledb via mTLS

### 4. **timescaledb** (PostgreSQL Database)
- **Database Port**: 5432
- **Envoy Inbound TCP**: 15001 (mTLS for PostgreSQL protocol)
- **Envoy Outbound TCP**: 15006
- **Envoy Admin**: 9901
- **Protocol**: TCP proxy (PostgreSQL)

### 5. **envoy** (Edge Load Balancer)
- **HTTPS Port**: 8443 (external access)
- **Admin Port**: 8090
- **Connects to**: bookapi-mcp-server via mTLS (port 15001)

## Traffic Flow

### HTTP Service-to-Service
```
Client → Service App (localhost:5288/5289/80)
  → Envoy Sidecar (127.0.0.1:15006)
  → mTLS → Target Service Envoy (target:15001)
  → Target Service App (localhost:5288/5289/80)
```

### Database Connections
```
Application (bookapi/pgAdmin)
  → Envoy Sidecar (127.0.0.1:15007)
  → mTLS → TimescaleDB Envoy (timescaledb:15001)
  → PostgreSQL (localhost:5432)
```

### External Traffic
```
External Client
  → Edge Envoy (port 8443, HTTPS)
  → mTLS → bookapi-mcp-server Envoy (port 15001)
  → bookapi-mcp-server App (port 5289)
```

## Port Reference

| Service | App Port | Envoy Inbound | Envoy Outbound HTTP | Envoy Outbound TCP | Envoy Admin |
|---------|----------|---------------|---------------------|-------------------|-------------|
| bookapi | 5288 | 15001 | 15006 | 15007 | 9901 |
| bookapi-mcp-server | 5289 | 15001 | 15006 | - | 9901 |
| pgAdmin | 80 | 15001 | 15006 | 15007 | 9901 |
| timescaledb | 5432 | 15001 | - | 15006 | 9901 |
| envoy (edge) | - | 8443 | - | - | 8090 |

## Certificate Requirements

Each service needs its own mTLS certificate:
- `bookapi-mtls-cert`
- `bookapi-mcp-server-mtls-cert`
- `pgadmin-mtls-cert`
- `timescaledb-mtls-cert`
- `envoy-mtls-cert` (for edge Envoy)

All certificates are signed by the same CA: `service-mesh-ca`

## Deployment Steps

### 1. Generate Certificates

```bash
cd k8s/service-mesh
./generate-certs.sh
```

### 2. Create Secrets

```bash
# CA Secret
kubectl create secret generic service-mesh-ca \
  --from-file=ca.crt=./certs/ca.crt \
  --from-file=ca.key=./certs/ca.key

# Service Secrets
kubectl create secret generic bookapi-mtls-cert \
  --from-file=tls.crt=./certs/bookapi.crt \
  --from-file=tls.key=./certs/bookapi.key \
  --from-file=ca.crt=./certs/ca.crt

kubectl create secret generic bookapi-mcp-server-mtls-cert \
  --from-file=tls.crt=./certs/bookapi-mcp-server.crt \
  --from-file=tls.key=./certs/bookapi-mcp-server.key \
  --from-file=ca.crt=./certs/ca.crt

kubectl create secret generic pgadmin-mtls-cert \
  --from-file=tls.crt=./certs/pgadmin.crt \
  --from-file=tls.key=./certs/pgadmin.key \
  --from-file=ca.crt=./certs/ca.crt

kubectl create secret generic timescaledb-mtls-cert \
  --from-file=tls.crt=./certs/timescaledb.crt \
  --from-file=tls.key=./certs/timescaledb.key \
  --from-file=ca.crt=./certs/ca.crt

kubectl create secret generic envoy-mtls-cert \
  --from-file=tls.crt=./certs/envoy.crt \
  --from-file=tls.key=./certs/envoy.key \
  --from-file=ca.crt=./certs/ca.crt
```

### 3. Deploy Service Mesh

```bash
kubectl apply -k k8s/service-mesh/
```

### 4. Update Connection Strings

Update the bookapi ConfigMap to use the Envoy sidecar for database connections:

```bash
kubectl patch configmap bookapi-config --type merge -p '{"data":{"ConnectionStrings__DefaultConnection":"Host=127.0.0.1;Port=15007;Database=bookdb;Username=postgres;Password=${DB_PASSWORD}"}}'
```

## Configuration Files

### Envoy ConfigMaps
- `configmap-bookapi-envoy.yaml` - BookAPI sidecar config
- `configmap-bookapi-mcp-server-envoy.yaml` - MCP Server sidecar config
- `configmap-pgadmin-envoy.yaml` - pgAdmin sidecar config
- `configmap-timescaledb-envoy.yaml` - TimescaleDB sidecar config
- `envoy-edge-configmap.yaml` - Edge Envoy config

### Deployments
- `bookapi-deployment.yaml` - BookAPI with Envoy sidecar
- `bookapi-mcp-server-deployment.yaml` - MCP Server with Envoy sidecar
- `pgadmin-deployment.yaml` - pgAdmin with Envoy sidecar
- `timescaledb-deployment.yaml` - TimescaleDB with Envoy sidecar
- `envoy-edge-deployment.yaml` - Edge Envoy load balancer

### Services
- `bookapi-service.yaml` - Exposes ports 15001 (mTLS) and 5288 (direct)
- `bookapi-mcp-server-service.yaml` - Exposes ports 15001 (mTLS) and 5289 (direct)
- `pgadmin-service.yaml` - Exposes ports 15001 (mTLS) and 80 (direct)
- `timescaledb-service.yaml` - Exposes ports 15001 (mTLS) and 5432 (direct)

## Verification

### Check All Pods

```bash
kubectl get pods
# Each service pod should show 2/2 Ready (app + envoy sidecar)
```

### Test Service-to-Service Communication

```bash
# Test bookapi-mcp-server → bookapi
kubectl exec -it <bookapi-mcp-server-pod> -c bookapi-mcp-server -- \
  curl http://127.0.0.1:15006/books
```

### Test Database Connection

```bash
# Test bookapi → timescaledb
kubectl exec -it <bookapi-pod> -c bookapi -- \
  psql -h 127.0.0.1 -p 15007 -U postgres -d bookdb
```

### Check Envoy Logs

```bash
# View Envoy sidecar logs
kubectl logs <pod-name> -c envoy

# Check for mTLS handshakes
kubectl logs <pod-name> -c envoy | grep -i tls
```

## Security Benefits

✅ **All inter-service traffic encrypted with mTLS**
✅ **Certificate-based service authentication**
✅ **Service identity verification via SANs**
✅ **Database connections encrypted**
✅ **Edge-to-backend communication encrypted**
✅ **Defense in depth with network policies**

## Important Notes

1. **Database Connections**: Applications must connect to `127.0.0.1:15007` (not `timescaledb:5432`) to use the service mesh
2. **HTTP Connections**: Applications connect to `127.0.0.1:15006` for HTTP traffic
3. **Direct Access**: Services still expose original ports for direct access if needed (not recommended for production)
4. **Certificate Rotation**: Plan for certificate rotation (consider using cert-manager)
5. **Performance**: Envoy sidecars add minimal latency (~1-2ms per hop)

## Troubleshooting

See individual service documentation:
- `README.md` - General service mesh documentation
- `MIGRATION.md` - Migration guide
- `DATABASE_CONNECTION.md` - Database connection details
- `QUICKSTART.md` - Quick reference

