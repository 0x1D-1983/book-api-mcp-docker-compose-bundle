# Service Mesh Architecture

## Overview

This service mesh implementation uses Envoy sidecars to provide mTLS encryption and service-to-service communication management.

## Architecture Diagram

```
┌────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                      │
│                                                            │
│  ┌──────────────────────┐      ┌──────────────────────┐    │
│  │  bookapi-mcp-server  │      │      bookapi         │    │
│  │                      │      │                      │    │
│  │  ┌──────────────┐    │      │  ┌──────────────┐    │    │
│  │  │ Application  │    │      │  │ Application  │    │    │
│  │  │ (Port 5289)  │    │      │  │ (Port 5288)  │    │    │
│  │  └──────┬───────┘    │      │  └──────┬───────┘    │    │
│  │         │            │      │         │            │    │
│  │  ┌──────▼───────┐    │      │  ┌──────▼───────┐    │    │
│  │  │ Envoy Sidecar│    │      │  │ Envoy Sidecar│    │    │
│  │  │              │    │      │  │              │    │    │
│  │  │ In: 15001    │    │      │  │ In: 15001    │    │    │
│  │  │ Out: 15006   │    │      │  │ Out: 15006   │    │    │
│  │  │ Admin: 9901  │    │      │  │ Admin: 9901  │    │    │
│  │  └──────┬───────┘    │      │  └──────┬───────┘    │    │
│  └─────────┼────────────┘      └─────────┼────────────┘    │
│            │                             │                 │
│            │   mTLS (Port 15001)         │                 │
│            └─────────────────────────────┘                 │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

## Traffic Flow

### Inbound Traffic (External → Service)

1. External client connects to service on port 15001 (Envoy sidecar)
2. Envoy performs mTLS handshake (requires client certificate)
3. Envoy validates client certificate against CA
4. Envoy forwards decrypted traffic to application on localhost:5288/5289

### Outbound Traffic (Service → Service)

1. Application makes HTTP request to `http://127.0.0.1:15006`
2. Envoy sidecar intercepts on port 15006
3. Envoy routes to target service's Envoy sidecar on port 15001
4. Envoy establishes mTLS connection with target service
5. Target Envoy sidecar validates certificate and forwards to application

## Components

### Envoy Sidecar

Each service pod includes an Envoy sidecar container that:

- **Inbound Listener (15001)**: Receives mTLS-encrypted traffic from other services
- **Outbound Listener (15006)**: Intercepts outbound traffic from the application
- **Admin Interface (9901)**: Provides metrics, stats, and configuration

### Certificate Management

- **CA Certificate**: Root certificate authority for the service mesh
- **Service Certificates**: Individual certificates for each service
- **Certificate Validation**: Envoy validates certificates using:
  - CA certificate trust
  - Subject Alternative Names (SANs) matching service names

### Service Discovery

Services discover each other via Kubernetes DNS:
- `bookapi.default.svc.cluster.local`
- `bookapi-mcp-server.default.svc.cluster.local`

## Security Model

### mTLS Configuration

- **Client Certificate Required**: `require_client_certificate: true`
- **Certificate Validation**: Validates against CA and checks SANs
- **SAN Matching**: Only allows connections from authorized services

### Certificate SANs

Each service certificate includes:
- Service name (e.g., `bookapi`)
- FQDN (e.g., `bookapi.default.svc.cluster.local`)

### Network Isolation

- Services communicate only through Envoy sidecars
- Direct service-to-service communication is blocked
- All traffic is encrypted with mTLS

## Configuration Files

### Deployments
- `bookapi-deployment.yaml`: BookAPI with Envoy sidecar
- `bookapi-mcp-server-deployment.yaml`: MCP Server with Envoy sidecar

### Services
- `bookapi-service.yaml`: Exposes BookAPI on ports 15001 (mTLS) and 5288 (direct)
- `bookapi-mcp-server-service.yaml`: Exposes MCP Server on ports 15001 (mTLS) and 5289 (direct)

### Envoy Configurations
- `configmap-bookapi-envoy.yaml`: Envoy config for BookAPI
- `configmap-bookapi-mcp-server-envoy.yaml`: Envoy config for MCP Server

### Certificates
- `cert-manager.yaml`: Kubernetes secrets for certificates
- `generate-certs.sh`: Script to generate certificates

## Benefits

1. **Security**: All inter-service traffic encrypted with mTLS
2. **Authentication**: Certificate-based service identity
3. **Observability**: Envoy provides metrics and logging
4. **Traffic Management**: Centralized routing and load balancing
5. **Policy Enforcement**: Can add rate limiting, circuit breakers, etc.

## Limitations

1. **Resource Overhead**: Each pod requires additional resources for Envoy
2. **Complexity**: More moving parts to manage
3. **Certificate Management**: Requires certificate rotation strategy
4. **Latency**: Small additional latency (~1-2ms per hop)

## Future Enhancements

- [ ] Automatic certificate rotation with cert-manager
- [ ] Service mesh observability (metrics, tracing, logging)
- [ ] Traffic policies (rate limiting, circuit breakers)
- [ ] Service mesh dashboard
- [ ] Zero-trust network policies
- [ ] Automatic sidecar injection (e.g., Istio-style)

