# Database Connection Configuration for Service Mesh

When using the service mesh with mTLS, database connections need to be updated to use the Envoy sidecar.

## TimescaleDB Connection

The TimescaleDB service now has an Envoy sidecar that proxies PostgreSQL connections with mTLS.

### Connection String Format

**Before (Direct Connection):**
```
Host=timescaledb;Port=5432;Database=bookdb;Username=postgres;Password=...
```

**After (Service Mesh with mTLS):**
```
Host=127.0.0.1;Port=15007;Database=bookdb;Username=postgres;Password=...
```

**Note:** Port 15007 is the TCP proxy port for database connections. Port 15006 is for HTTP traffic.

### How It Works

1. Application connects to `127.0.0.1:15007` (Envoy TCP outbound listener)
2. Envoy sidecar intercepts the connection
3. Envoy establishes mTLS connection to `timescaledb:15001` (target service's Envoy sidecar)
4. Target Envoy sidecar validates certificate and forwards to PostgreSQL on `127.0.0.1:5432`

### Updating Connection Strings

Update the `bookapi` ConfigMap to use the Envoy sidecar:

```bash
kubectl patch configmap bookapi-config --type merge -p '{"data":{"ConnectionStrings__DefaultConnection":"Host=127.0.0.1;Port=15007;Database=bookdb;Username=postgres;Password=${DB_PASSWORD}"}}'
```

**Note:** The password should still come from the secret. Only the Host and Port need to change.

### Alternative: Direct Connection (Not Recommended)

If you need to bypass the service mesh for database connections (not recommended for production), you can still connect directly:

```
Host=timescaledb;Port=5432;...
```

The service exposes both ports:
- Port `15001`: mTLS endpoint (via Envoy sidecar)
- Port `5432`: Direct database access

## pgAdmin Access

pgAdmin can access TimescaleDB through the service mesh:

1. In pgAdmin, configure server connection:
   - **Host**: `127.0.0.1` (uses Envoy sidecar)
   - **Port**: `15007` (Envoy TCP outbound port)
   - **Database**: Your database name
   - **Username/Password**: As configured

2. pgAdmin's Envoy sidecar will handle the mTLS connection to TimescaleDB

## Verification

### Test Database Connection via Service Mesh

```bash
# Exec into bookapi pod
kubectl exec -it <bookapi-pod> -c bookapi -- sh

# Test connection (if psql is available)
psql -h 127.0.0.1 -p 15007 -U postgres -d bookdb
```

### Check Envoy Logs

```bash
# View Envoy sidecar logs for database connections
kubectl logs <timescaledb-pod> -c envoy | grep -i tcp
kubectl logs <bookapi-pod> -c envoy | grep -i tcp
```

## Security Benefits

- ✅ Database connections encrypted with mTLS
- ✅ Certificate-based authentication
- ✅ Service identity verification
- ✅ All database traffic goes through Envoy (observability)

## Troubleshooting

### Connection Refused

- Verify Envoy sidecar is running: `kubectl get pods -c envoy`
- Check Envoy logs for errors
- Verify connection string uses `127.0.0.1:15007`

### Certificate Errors

- Ensure certificates are valid: `kubectl get secret timescaledb-mtls-cert`
- Check Envoy logs for TLS handshake errors
- Verify CA certificate is in the secret

### Connection Timeout

- Verify service endpoints: `kubectl get endpoints timescaledb`
- Check network policies aren't blocking traffic
- Verify Envoy sidecar can reach target service

