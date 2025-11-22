# Edge Envoy Routing Configuration

The edge Envoy load balancer routes external traffic to backend services based on path prefixes.

## Routes

### pgAdmin
- **Path**: `/pgadmin` or `/pgadmin/*`
- **Backend**: `pgadmin:15001` (via mTLS)
- **Access**: `https://<edge-envoy-ip>:8443/pgadmin`

The `/pgadmin` prefix is stripped before forwarding to pgAdmin, so pgAdmin receives requests at its root path.

### bookapi-mcp-server (Default)
- **Path**: `/` (everything else)
- **Backend**: `bookapi-mcp-server:15001` (via mTLS)
- **Access**: `https://<edge-envoy-ip>:8443/`

## Access URLs

### External Access via Edge Envoy

1. **pgAdmin**:
   ```
   https://<edge-envoy-external-ip>:8443/pgadmin
   ```

2. **bookapi-mcp-server**:
   ```
   https://<edge-envoy-external-ip>:8443/
   ```

### Finding the Edge Envoy External IP

```bash
# Get the external IP
kubectl get service envoy

# Or if using LoadBalancer
kubectl get svc envoy -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

## Routing Details

### Path Matching

Routes are matched in order:
1. `/pgadmin` prefix → routes to pgAdmin
2. `/` (catch-all) → routes to bookapi-mcp-server

### Path Rewriting

- **pgAdmin**: The `/pgadmin` prefix is stripped using `prefix_rewrite: "/"`, so pgAdmin receives requests at `/`
- **bookapi-mcp-server**: No path rewriting, requests pass through as-is

### Timeouts

- **pgAdmin**: 300 seconds (5 minutes) - longer timeout for database operations
- **bookapi-mcp-server**: Default timeout

## Security

All backend connections use mTLS:
- Edge Envoy presents its certificate to backend services
- Backend services validate the certificate against the CA
- Certificate SANs are checked for service identity

## Adding New Routes

To add a new route, update `envoy-edge-configmap.yaml`:

1. Add a route match in the `routes` section (before the catch-all):
   ```yaml
   - match:
       prefix: "/new-service"
     route:
       cluster: new-service
   ```

2. Add a cluster definition:
   ```yaml
   - name: new-service
     connect_timeout: 0.5s
     type: STRICT_DNS
     dns_lookup_family: V4_ONLY
     lb_policy: ROUND_ROBIN
     load_assignment:
       cluster_name: new-service
       endpoints:
       - lb_endpoints:
         - endpoint:
             address:
               socket_address:
                 address: new-service.default.svc.cluster.local
                 port_value: 15001
     transport_socket:
       name: envoy.transport_sockets.tls
       typed_config:
         "@type": type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.UpstreamTlsContext
         common_tls_context:
           tls_certificates:
             - certificate_chain:
                 filename: /etc/ssl/envoy/tls.crt
               private_key:
                 filename: /etc/ssl/envoy/tls.key
           validation_context:
             trusted_ca:
               filename: /etc/ssl/envoy/ca.crt
             match_subject_alt_names:
               - exact: new-service
               - exact: new-service.default.svc.cluster.local
   ```

## Troubleshooting

### Route Not Working

1. Check Envoy logs:
   ```bash
   kubectl logs <envoy-pod> | grep -i route
   ```

2. Verify the route is configured:
   ```bash
   kubectl get configmap envoy-conf -o yaml
   ```

3. Test connectivity:
   ```bash
   # Test pgAdmin route
   curl -k https://<edge-ip>:8443/pgadmin
   
   # Test default route
   curl -k https://<edge-ip>:8443/
   ```

### Certificate Issues

- Verify edge Envoy has the certificate:
  ```bash
  kubectl get secret envoy-mtls-cert
  ```

- Check Envoy logs for TLS errors:
  ```bash
  kubectl logs <envoy-pod> | grep -i tls
  ```

### Path Rewriting Issues

If pgAdmin doesn't load correctly:
- Check if static assets are being served correctly
- Verify the `prefix_rewrite` is working
- Check pgAdmin logs for 404 errors

## Alternative: Host-Based Routing

If you prefer host-based routing instead of path-based, you can configure:

```yaml
virtual_hosts:
- name: pgadmin
  domains:
  - "pgadmin.example.com"
  routes:
  - match:
      prefix: "/"
    route:
      cluster: pgadmin
- name: bookapi
  domains:
  - "api.example.com"
  routes:
  - match:
      prefix: "/"
    route:
      cluster: bookapi-mcp-server
```

This requires DNS configuration and is more suitable for production environments.

