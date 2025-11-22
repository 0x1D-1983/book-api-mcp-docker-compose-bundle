# Edge Envoy to pgAdmin mTLS Connection Failure

## Problem

When accessing `https://127.0.0.1/pgadmin/login?next=/` through the edge Envoy, you get the error:

```
upstream connect error or disconnect/reset before headers. 
reset reason: remote connection failure, 
transport failure reason: TLS_error:|268435581:SSL routines:OPENSSL_internal:CERTIFICATE_VERIFY_FAILED
```

## Root Cause

The `pgadmin-mtls-cert` secret contains a **different CA certificate** than the one used to sign the actual certificates. This causes the edge Envoy to fail when verifying the pgadmin certificate during the mTLS handshake.

### Certificate Chain

1. **Edge Envoy** uses `envoy-mtls-cert` secret (has CA: `87:4A:C2:58:...`)
2. **pgAdmin sidecar** uses `pgadmin-mtls-cert` secret (has CA: `E2:CB:01:A3:...`)
3. **Actual certificates** were signed with CA: `87:4A:C2:58:...`

When the edge Envoy tries to verify pgadmin's certificate, it uses the CA from `envoy-mtls-cert` (`87:4A:C2:58:...`), but the pgadmin certificate was signed with a different CA, causing verification to fail.

## Solution

Update all secrets to use the **same CA certificate** that was used to sign all the service certificates.

### Quick Fix (Automated)

Run the comprehensive fix script:

```bash
cd k8s/service-mesh
./fix-all-certificates.sh
```

This script will:
1. Verify all certificates exist
2. Delete all placeholder/incorrect secrets
3. Create/update all secrets with the correct CA certificate
4. Restart all pods to pick up the new certificates

### Manual Fix

1. **Delete the incorrect secrets**:
   ```bash
   kubectl delete secret pgadmin-mtls-cert envoy-mtls-cert
   ```

2. **Create secrets with the correct CA**:
   ```bash
   cd k8s/service-mesh
   
   # pgAdmin secret (with correct CA)
   kubectl create secret generic pgadmin-mtls-cert \
     --from-file=tls.crt=./certs/pgadmin.crt \
     --from-file=tls.key=./certs/pgadmin.key \
     --from-file=ca.crt=./certs/ca.crt
   
   # Edge Envoy secret (with correct CA)
   kubectl create secret generic envoy-mtls-cert \
     --from-file=tls.crt=./certs/envoy.crt \
     --from-file=tls.key=./certs/envoy.key \
     --from-file=ca.crt=./certs/ca.crt
   ```

3. **Restart pods**:
   ```bash
   kubectl delete pod -l app=pgadmin
   kubectl delete pod -l app=envoy
   ```

## Verification

After applying the fix, verify that all secrets use the same CA:

```bash
# Check CA fingerprints (should all match)
kubectl get secret envoy-mtls-cert -o jsonpath='{.data.ca\.crt}' | base64 -d | openssl x509 -fingerprint -noout
kubectl get secret pgadmin-mtls-cert -o jsonpath='{.data.ca\.crt}' | base64 -d | openssl x509 -fingerprint -noout
kubectl get secret bookapi-mtls-cert -o jsonpath='{.data.ca\.crt}' | base64 -d | openssl x509 -fingerprint -noout

# Compare with local CA
openssl x509 -in k8s/service-mesh/certs/ca.crt -fingerprint -noout
```

All fingerprints should match.

## Why This Happens

This issue occurs when:
1. Secrets are created at different times with different CA certificates
2. The `cert-manager.yaml` file creates placeholder secrets that get partially updated
3. Certificates are regenerated but secrets aren't updated consistently

## Prevention

Always use the same CA certificate for all secrets in the service mesh. The `fix-all-certificates.sh` script ensures this by:
- Using the same `ca.crt` file for all secrets
- Regenerating all secrets from the same certificate directory
- Verifying certificates before creating secrets

## Related Issues

- If you see similar errors for other services (bookapi, bookapi-mcp-server, timescaledb), run `fix-all-certificates.sh` to fix all services at once
- The edge Envoy connects to all backend services with mTLS, so all services must use the same CA

