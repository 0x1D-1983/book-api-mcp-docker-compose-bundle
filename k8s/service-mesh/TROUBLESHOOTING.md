# Service Mesh Troubleshooting Guide

## Common Issues and Solutions

### Browser Certificate Warning for Edge Envoy

**Symptom:** Browser shows "Your connection is not private" or certificate warning when accessing `https://<edge-ip>:8443`

**Cause:** The edge Envoy uses a self-signed certificate for HTTPS, which browsers don't trust by default.

**Solution:** This is expected behavior. You have two options:

1. **Accept the warning** (for development/testing):
   - Click "Advanced" → "Proceed to site"
   - The connection is still encrypted, just not verified by a public CA

2. **Use a trusted certificate** (for production):
   - Obtain a certificate from a public CA (Let's Encrypt, etc.)
   - Or use a private CA that's trusted by your organization
   - Update the `envoy-mtls-cert` secret with the new certificate

**Note:** This browser warning does NOT affect upstream mTLS connections. The edge Envoy's server certificate and its client certificate for mTLS are separate concerns.

### Upstream mTLS Connection Failures

**Symptom:** `upstream connect error or disconnect/reset before headers. reset reason: remote connection failure, transport failure reason: TLS_error:|268435581:SSL routines:OPENSSL_internal:CERTIFICATE_VERIFY_FAILED`

**Important:** This error can be misleading! It may not be an SSL/certificate issue at all. Check for routing/configuration issues first, especially for services hosted under subdirectories (like pgAdmin).

**Possible Causes:**

0. **Misrouting due to subdirectory hosting (Common for pgAdmin):**
   - Service generates redirects to wrong path (e.g., `/` instead of `/subdirectory`)
   - Edge Envoy routes to wrong backend service (default route)
   - Service mesh blocks unauthorized service-to-service connection
   - **Solution:** Configure proper subdirectory hosting with `X-Script-Name` header and `prefix_rewrite`

1. **Client certificate not presented:**
   - Edge Envoy must have `tls_certificates` configured in `UpstreamTlsContext`
   - Verify the certificate file exists and is readable

2. **Certificate SAN mismatch:**
   - Client certificate SAN must match what the server expects
   - Check `match_subject_alt_names` in server configuration
   - Verify certificate has correct SANs: `openssl x509 -text -noout -in cert.crt | grep -A 5 "Subject Alternative Name"`

3. **CA certificate mismatch:**
   - Both client and server must trust the same CA
   - Verify CA fingerprints match:
     ```bash
     kubectl get secret <client-secret> -o jsonpath='{.data.ca\.crt}' | base64 -d | openssl x509 -fingerprint -noout
     kubectl get secret <server-secret> -o jsonpath='{.data.ca\.crt}' | base64 -d | openssl x509 -fingerprint -noout
     ```

4. **Certificate chain issues:**
   - For client certificates, use only the leaf certificate (not the full chain)
   - The CA should be in the validation context, not the certificate chain
   - Verify certificate format: `openssl verify -CAfile ca.crt cert.crt`

**Debugging Steps:**

1. **Check Envoy logs:**
   ```bash
   # Edge Envoy logs
   kubectl logs -l app=envoy | grep -i tls
   
   # Backend service Envoy logs
   kubectl logs -l app=<service> -c envoy | grep -i tls
   ```

2. **Verify certificates:**
   ```bash
   # Check certificate SANs
   kubectl exec <pod> -c envoy -- cat /etc/ssl/envoy/tls.crt | openssl x509 -text -noout | grep -A 5 "Subject Alternative Name"
   
   # Verify certificate validity
   kubectl exec <pod> -c envoy -- openssl verify -CAfile /etc/ssl/envoy/ca.crt /etc/ssl/envoy/tls.crt
   ```

3. **Test certificate presentation:**
   ```bash
   # Check if certificate is being read
   kubectl exec <pod> -c envoy -- ls -la /etc/ssl/envoy/
   kubectl exec <pod> -c envoy -- cat /etc/ssl/envoy/tls.crt | head -5
   ```

### Certificate Format Issues

**Problem:** Certificate chain has multiple certificates but Envoy can't parse it

**Solution:** 
- For client certificates in mTLS, use only the leaf certificate
- The CA certificate should be in the `validation_context.trusted_ca` field, not in the certificate chain
- For server certificates, you can include the full chain

### Service Discovery Issues

**Symptom:** Connection fails with DNS resolution errors

**Solution:**
- Verify service DNS names: `<service>.<namespace>.svc.cluster.local`
- Check service endpoints: `kubectl get endpoints <service>`
- Verify service selector matches pod labels

### Port Configuration Issues

**Symptom:** Connection refused or wrong service responding

**Solution:**
- Verify service mesh ports:
  - Inbound: 15001 (mTLS)
  - Outbound HTTP: 15006
  - Outbound TCP: 15007 (for databases)
  - Admin: 9901
- Check service port mappings: `kubectl get svc <service> -o yaml`

## Quick Diagnostic Commands

```bash
# Check all pods with Envoy sidecars
kubectl get pods -o wide | grep -E "bookapi|pgadmin|timescaledb|envoy"

# Check Envoy sidecar status
kubectl get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[*].name}{"\n"}{end}' | grep envoy

# View Envoy admin interface
kubectl port-forward <pod-name> 9901:9901
# Then visit http://localhost:9901/stats

# Check certificate expiration
kubectl exec <pod> -c envoy -- cat /etc/ssl/envoy/tls.crt | openssl x509 -noout -dates

# Test mTLS connection manually
kubectl exec <client-pod> -c <app> -- curl -v https://<service>:15001/health
```

## Getting Help

If issues persist:
1. Collect Envoy logs with debug level: `--component-log-level upstream:debug,connection:trace`
2. Check certificate details and SANs
3. Verify all services are using the same CA
4. Check network policies aren't blocking traffic
5. Review Envoy configuration for syntax errors

