#!/usr/bin/env bash
# Deja la plataforma del TFM lista sobre un K3s recién instalado:
#   1. Argo CD
#   2. Argo Rollouts
#   3. Secret con la contraseña de Grafana (no va en Git: el repo es público)
#   4. Las Applications de Argo CD (tfm y observability), leídas de tfm-gitops en GitHub
# A partir de ahí, Argo CD despliega el resto desde Git.
#
# Se puede ejecutar varias veces sin romper nada (idempotente).
# Se usa igual en la VM de Vagrant y, más adelante, en la EC2.
set -euo pipefail

ARGOCD_VERSION="${ARGOCD_VERSION:-v3.6.2}"
ROLLOUTS_VERSION="${ROLLOUTS_VERSION:-v1.10.2}"
GITOPS_RAW="${GITOPS_RAW:-https://raw.githubusercontent.com/arieldevops2026/tfm-gitops/main}"

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

ns() { kubectl create namespace "$1" --dry-run=client -o yaml | kubectl apply -f - >/dev/null; }

# Espera a que un CRD exista y esté aceptado por la API
esperar_crd() {
  for _ in $(seq 1 60); do
    kubectl get crd "$1" >/dev/null 2>&1 && break
    sleep 5
  done
  kubectl wait --for=condition=Established "crd/$1" --timeout=120s >/dev/null
}

echo "==> 1/4 Argo CD ${ARGOCD_VERSION}"
ns argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml" >/dev/null

echo "==> 2/4 Argo Rollouts ${ROLLOUTS_VERSION}"
ns argo-rollouts
kubectl apply -n argo-rollouts --server-side --force-conflicts \
  -f "https://github.com/argoproj/argo-rollouts/releases/download/${ROLLOUTS_VERSION}/install.yaml" >/dev/null

echo "==> 3/4 Secret de Grafana"
ns observability
if ! kubectl -n observability get secret grafana-admin >/dev/null 2>&1; then
  GRAFANA_PW="$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 16)"
  kubectl -n observability create secret generic grafana-admin \
    --from-literal=password="$GRAFANA_PW" >/dev/null
  echo "    creado"
else
  echo "    ya existía, no se cambia"
fi

echo "==> 4/4 Applications de Argo CD"
# Las Applications usan CRDs de Argo CD, y los manifiestos de tfm usan CRDs de
# Argo Rollouts y de Traefik (este último lo instala K3s por su cuenta, puede tardar).
for crd in applications.argoproj.io rollouts.argoproj.io analysistemplates.argoproj.io \
           ingressroutes.traefik.io traefikservices.traefik.io; do
  esperar_crd "$crd"
done
kubectl apply -f "${GITOPS_RAW}/argocd/observability-app.yaml" >/dev/null
kubectl apply -f "${GITOPS_RAW}/argocd/tfm-app.yaml" >/dev/null

echo "==> Esperando a que Argo CD sincronice (máx. 8 min)"
for _ in $(seq 1 96); do
  ESTADO="$(kubectl -n argocd get applications -o jsonpath='{range .items[*]}{.status.sync.status}/{.status.health.status} {end}' 2>/dev/null || true)"
  [ "$ESTADO" = "Synced/Healthy Synced/Healthy " ] && break
  sleep 5
done
kubectl -n argocd get applications

echo
echo "================ Accesos ================"
echo "Grafana:  http://192.168.56.20/grafana   usuario admin"
echo "          contraseña: $(kubectl -n observability get secret grafana-admin -o jsonpath='{.data.password}' | base64 -d)"
for _ in $(seq 1 30); do
  kubectl -n argocd get secret argocd-initial-admin-secret >/dev/null 2>&1 && break
  sleep 5
done
echo "Argo CD:  usuario admin"
echo "          contraseña: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo '(aún no disponible)')"
echo "          abrir con: vagrant ssh -c \"kubectl -n argocd port-forward --address 0.0.0.0 svc/argocd-server 8080:443\""
echo "          y entrar en https://192.168.56.20:8080"
echo "========================================="
