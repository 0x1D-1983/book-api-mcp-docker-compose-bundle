#!/bin/bash
# Script to create a combined certificate chain for edge Envoy
# This includes both the leaf certificate and the CA certificate

set -e

SECRET_NAME="envoy-mtls-cert"
NAMESPACE="default"

echo "Creating combined certificate chain for edge Envoy..."

# Get the current certificate and CA
TLS_CRT=$(kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.tls\.crt}' | base64 -d)
CA_CRT=$(kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.ca\.crt}' | base64 -d)

# Combine them (leaf first, then CA)
COMBINED_CRT="$TLS_CRT
$CA_CRT"

# Update the secret with the combined certificate
kubectl create secret generic $SECRET_NAME \
  --from-literal=tls.crt="$COMBINED_CRT" \
  --from-file=tls.key=<(kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.tls\.key}' | base64 -d) \
  --from-file=ca.crt=<(echo "$CA_CRT") \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Certificate chain updated. Restarting edge Envoy pods..."
kubectl rollout restart deployment/envoy -n $NAMESPACE

echo "Done!"

