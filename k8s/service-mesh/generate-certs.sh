#!/bin/bash
# Script to generate mTLS certificates for service mesh
# This generates a CA and certificates for each service

set -e

CERT_DIR="./certs"
mkdir -p "$CERT_DIR"

# Generate CA private key
echo "Generating CA private key..."
openssl genrsa -out "$CERT_DIR/ca.key" 4096

# Generate CA certificate
echo "Generating CA certificate..."
openssl req -new -x509 -days 365 -key "$CERT_DIR/ca.key" -out "$CERT_DIR/ca.crt" \
  -subj "/CN=service-mesh-ca/O=ServiceMesh"

# Function to generate service certificate
generate_service_cert() {
  local service_name=$1
  local common_name=$2
  
  echo "Generating certificate for $service_name..."
  
  # Generate private key
  openssl genrsa -out "$CERT_DIR/${service_name}.key" 2048
  
  # Generate CSR
  openssl req -new -key "$CERT_DIR/${service_name}.key" -out "$CERT_DIR/${service_name}.csr" \
    -subj "/CN=${common_name}/O=ServiceMesh"
  
  # Create certificate with SANs
  cat > "$CERT_DIR/${service_name}.conf" <<EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${common_name}
DNS.2 = ${common_name}.default.svc.cluster.local
DNS.3 = ${common_name}.default
DNS.4 = ${common_name}.svc.cluster.local
EOF
  
  # Sign certificate with CA
  openssl x509 -req -in "$CERT_DIR/${service_name}.csr" \
    -CA "$CERT_DIR/ca.crt" \
    -CAkey "$CERT_DIR/ca.key" \
    -CAcreateserial \
    -out "$CERT_DIR/${service_name}.crt" \
    -days 365 \
    -extensions v3_req \
    -extfile "$CERT_DIR/${service_name}.conf"
  
  # Clean up
  rm "$CERT_DIR/${service_name}.csr" "$CERT_DIR/${service_name}.conf"
}

# Generate certificates for services
generate_service_cert "bookapi" "bookapi"
generate_service_cert "bookapi-mcp-server" "bookapi-mcp-server"

echo ""
echo "Certificates generated in $CERT_DIR/"
echo ""
echo "To create Kubernetes secrets, run:"
echo ""
echo "# CA Secret"
echo "kubectl create secret generic service-mesh-ca \\"
echo "  --from-file=ca.crt=$CERT_DIR/ca.crt \\"
echo "  --from-file=ca.key=$CERT_DIR/ca.key"
echo ""
echo "# BookAPI Secret"
echo "kubectl create secret generic bookapi-mtls-cert \\"
echo "  --from-file=tls.crt=$CERT_DIR/bookapi.crt \\"
echo "  --from-file=tls.key=$CERT_DIR/bookapi.key \\"
echo "  --from-file=ca.crt=$CERT_DIR/ca.crt"
echo ""
echo "# BookAPI MCP Server Secret"
echo "kubectl create secret generic bookapi-mcp-server-mtls-cert \\"
echo "  --from-file=tls.crt=$CERT_DIR/bookapi-mcp-server.crt \\"
echo "  --from-file=tls.key=$CERT_DIR/bookapi-mcp-server.key \\"
echo "  --from-file=ca.crt=$CERT_DIR/ca.crt"

