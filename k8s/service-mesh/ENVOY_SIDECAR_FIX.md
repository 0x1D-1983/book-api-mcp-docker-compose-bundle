# Envoy Sidecar Startup Failure - Root Cause and Fix

## Problem Summary

The Envoy sidecars in `bookapi` and `bookapi-mcp-server` pods fail to start because they're trying to load **placeholder certificates** from Kubernetes secrets instead of real certificates.

## Root Cause

1. **Placeholder Secrets**: The `cert-manager.yaml` file creates secrets with placeholder base64-encoded values:
   - `bookapi-mtls-cert` 
   - `bookapi-mcp-server-mtls-cert`
   
   These placeholders decode to just certificate headers/footers (e.g., `-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----`) without actual certificate data.

2. **Envoy Configuration**: The Envoy sidecars are configured to load certificates from:
   - `/etc/envoy/certs/tls.crt` (certificate chain)
   - `/etc/envoy/certs/tls.key` (private key)
   - `/etc/envoy/certs/ca.crt` (CA certificate)

3. **Failure Point**: When Envoy tries to parse these placeholder certificates, it fails with errors like:
   - `unable to load certificate chain`
   - `certificate verify failed`
   - `failed to load CA certificate`

## Solution

Replace the placeholder secrets with real certificates generated using the `generate-certs.sh` script.

### Quick Fix (Automated)

Run the fix script:

```bash
cd k8s/service-mesh
./fix-envoy-certificates.sh
```

This script will:
1. Generate certificates if they don't exist
2. Delete the placeholder secrets
3. Create new secrets with real certificates
4. Restart the pods

### Manual Fix

1. **Generate certificates** (if not already done):
   ```bash
   cd k8s/service-mesh
   ./generate-certs.sh
   ```

2. **Delete placeholder secrets**:
   ```bash
   kubectl delete secret bookapi-mtls-cert bookapi-mcp-server-mtls-cert
   ```

3. **Create secrets with real certificates**:
   ```bash
   kubectl create secret generic bookapi-mtls-cert \
     --from-file=tls.crt=./certs/bookapi.crt \
     --from-file=tls.key=./certs/bookapi.key \
     --from-file=ca.crt=./certs/ca.crt

   kubectl create secret generic bookapi-mcp-server-mtls-cert \
     --from-file=tls.crt=./certs/bookapi-mcp-server.crt \
     --from-file=tls.key=./certs/bookapi-mcp-server.key \
     --from-file=ca.crt=./certs/ca.crt
   ```

4. **Restart pods** to pick up new certificates:
   ```bash
   kubectl delete pod -l app=bookapi
   kubectl delete pod -l app=bookapi-mcp-server
   ```

## Verification

After applying the fix, verify the sidecars are running:

```bash
# Check pod status (should show 2/2 containers running)
kubectl get pods -l app=bookapi
kubectl get pods -l app=bookapi-mcp-server

# Check Envoy logs (should show "starting main dispatch loop")
kubectl logs <pod-name> -c envoy --tail=20
```

## Prevention

To prevent this issue in the future:

1. **Option 1**: Remove `cert-manager.yaml` from `kustomization.yaml` and create secrets manually after generating certificates
2. **Option 2**: Keep `cert-manager.yaml` but always run `fix-envoy-certificates.sh` after applying the service mesh configuration
3. **Option 3**: Use a proper certificate management solution (e.g., cert-manager operator) that generates real certificates automatically

## Diagnostic Tools

Use the diagnostic script to check the current state:

```bash
cd k8s/service-mesh
./diagnose-envoy-sidecars.sh
```

This will show:
- Pod status and container states
- Envoy logs
- Secret existence and content validation
- ConfigMap existence
- Volume mount configuration
- Local certificate file status

## Additional Notes

- The certificates are already generated in `k8s/service-mesh/certs/` directory
- The placeholder secrets are created when `kubectl apply -k k8s/service-mesh/` is run (because `cert-manager.yaml` is included in `kustomization.yaml`)
- Real certificates must be created **after** applying the service mesh configuration, or the placeholder secrets must be replaced
- The fix script handles all of this automatically

