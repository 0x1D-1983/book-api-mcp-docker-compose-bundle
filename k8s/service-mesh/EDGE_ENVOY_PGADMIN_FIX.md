# Edge Envoy to pgAdmin Connection Issues

## Problem

When accessing `https://<edge-ip>:8443/pgadmin` through the edge Envoy, you may see errors like:

```
upstream connect error or disconnect/reset before headers. 
reset reason: remote connection failure, 
transport failure reason: TLS_error:|268435581:SSL routines:OPENSSL_internal:CERTIFICATE_VERIFY_FAILED
```

**Note:** This error can be misleading - it may not actually be an SSL/certificate issue!

## Root Cause

The SSL error is often a **symptom, not the root cause**. The actual issue is typically:

### pgAdmin Subdirectory Hosting Misconfiguration

When pgAdmin is hosted under a subdirectory (`/pgadmin`) but not properly configured:

1. **pgAdmin generates incorrect redirects**: Without proper subdirectory configuration, pgAdmin redirects to `/` instead of `/pgadmin`
2. **Edge Envoy routes to wrong service**: The edge Envoy's default route (`/`) sends these redirects to `bookapi-mcp-server` instead of pgAdmin
3. **Service mesh blocks unauthorized connections**: pgAdmin's Envoy sidecar tries to connect to `bookapi-mcp-server`, but this connection is not allowed in the service mesh
4. **SSL error appears**: The connection failure manifests as an SSL error, but the real issue is the misrouting

### Certificate Issues (Less Common)

In some cases, the `pgadmin-mtls-cert` secret may contain a **different CA certificate** than the one used to sign the actual certificates. This causes the edge Envoy to fail when verifying the pgadmin certificate during the mTLS handshake.

### Certificate Chain

1. **Edge Envoy** uses `envoy-mtls-cert` secret (has CA: `87:4A:C2:58:...`)
2. **pgAdmin sidecar** uses `pgadmin-mtls-cert` secret (has CA: `E2:CB:01:A3:...`)
3. **Actual certificates** were signed with CA: `87:4A:C2:58:...`

When the edge Envoy tries to verify pgadmin's certificate, it uses the CA from `envoy-mtls-cert` (`87:4A:C2:58:...`), but the pgadmin certificate was signed with a different CA, causing verification to fail.

## Solution

### Fix 1: Configure pgAdmin Subdirectory Hosting (Most Common)

The primary fix is to properly configure pgAdmin for subdirectory hosting in the edge Envoy:

**In `envoy-edge-configmap.yaml`, the pgAdmin route must:**
1. Strip the `/pgadmin` prefix when forwarding: `prefix_rewrite: "/"`
2. Add the `X-Script-Name` header: `X-Script-Name: /pgadmin` (tells pgAdmin its base path)
3. Add the `X-Scheme` header: `X-Scheme: https` (tells pgAdmin to generate HTTPS URLs)

Example configuration:
```yaml
- match:
    prefix: "/pgadmin"
  route:
    cluster: pgadmin
    prefix_rewrite: "/"
    request_headers_to_add:
      - header:
          key: X-Script-Name
          value: /pgadmin
      - header:
          key: X-Scheme
          value: https
```

This matches the NGINX reverse proxy configuration for pgAdmin subdirectory hosting.

**Why this fixes it:**
- pgAdmin now knows it's under `/pgadmin` and generates correct URLs
- Redirects go to `/pgadmin/login` instead of `/login`
- Edge Envoy correctly routes these requests back to pgAdmin
- No misrouting to `bookapi-mcp-server`, so no SSL errors

### Fix 2: Update Certificate Secrets (If Certificate Issue)

If the issue persists after fixing subdirectory hosting, update all secrets to use the **same CA certificate** that was used to sign all the service certificates.

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

