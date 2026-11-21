#!/usr/bin/env bash
# Instala K3s de un solo nodo con versión fijada.
# Se usa igual en la VM de Vagrant y, más adelante, como user_data de la EC2.
set -euo pipefail

K3S_VERSION="${K3S_VERSION:-v1.36.6+k3s1}"

if command -v k3s >/dev/null 2>&1; then
  echo "K3s ya está instalado: $(k3s --version | head -1)"
  exit 0
fi

# Traefik viene incluido en K3s y es el ingress del TFM.
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="${K3S_VERSION}" \
  K3S_KUBECONFIG_MODE="644" \
  sh -s - server

# Esperar a que el nodo esté Ready
for i in $(seq 1 60); do
  if k3s kubectl get nodes 2>/dev/null | grep -q " Ready"; then
    k3s kubectl get nodes
    exit 0
  fi
  sleep 5
done

echo "El nodo no llegó a Ready" >&2
exit 1
