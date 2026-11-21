#!/usr/bin/env bash
# Cambia el escenario con el que se despliega ms-orders.
#   b0  rolling update nativo de Kubernetes (Deployment), sin canary ni SLO
#   b2  canary con pasos de tiempo fijos, sin análisis de SLO
#   b1  canary gobernado por SLO (AnalysisTemplate)
#
# Uso (desde tu equipo o dentro de la VM):  ./cambiar-escenario.sh b0|b1|b2
#
# Qué hace: cambia el "path" de la Application tfm de Argo CD hacia apps/tfm/overlays/<escenario>.
# Argo CD aplica la diferencia. El cambio NO es instantáneo ni sin interrupción: al pasar de un
# tipo de objeto a otro (Deployment <-> Rollout) hay unos segundos en los que ms-orders puede
# no responder. Está pensado para usarse ENTRE experimentos, no durante uno.
set -euo pipefail

ESC="${1:-}"
case "$ESC" in
  b0|b1|b2) ;;
  *) echo "Uso: $0 b0|b1|b2" >&2; exit 2 ;;
esac

# Este script solo debe tocar el clúster de la VM del TFM. Si se ejecuta en el equipo anfitrión
# se relanza dentro de la VM. Se decide por el nombre de la máquina y NO por si existe kubectl:
# en el equipo anfitrión hay un kubectl con el kubeconfig de otros clústeres que no se debe usar.
if [ "$(hostname)" != "tfm-k3s" ]; then
  cd "$(dirname "$0")/.."
  exec vagrant ssh -c "bash /vagrant/scripts/cambiar-escenario.sh $ESC"
fi

NS=tfm
RUTA="apps/tfm/overlays/${ESC}"
ACTUAL="$(kubectl -n argocd get application tfm -o jsonpath='{.spec.source.path}')"
echo "Escenario actual: ${ACTUAL}"
echo "Escenario nuevo:  ${RUTA}"

kubectl -n argocd patch application tfm --type merge \
  -p "{\"spec\":{\"source\":{\"path\":\"${RUTA}\"}}}" >/dev/null
kubectl -n argocd annotate application tfm argocd.argoproj.io/refresh=hard --overwrite >/dev/null

# Argo Rollouts añade a los Services un selector con el hash de la versión estable. Al salir de
# un Rollout (hacia B0) ese selector queda y los pods del Deployment no lo tienen: hay que quitarlo.
quitar_selector_residual() {
  for svc in ms-orders; do
    if kubectl -n "$NS" get svc "$svc" -o jsonpath='{.spec.selector}' 2>/dev/null | grep -q rollouts-pod-template-hash; then
      kubectl -n "$NS" patch svc "$svc" --type=json \
        -p '[{"op":"remove","path":"/spec/selector/rollouts-pod-template-hash"}]' >/dev/null
      echo "  Selector residual de Argo Rollouts retirado del Service ${svc}"
    fi
  done
}

echo "Esperando a que Argo CD aplique el escenario..."
for i in $(seq 1 90); do
  sleep 2
  PATH_APP="$(kubectl -n argocd get application tfm -o jsonpath='{.status.sync.status} {.status.health.status} {.status.sync.revision}' 2>/dev/null || true)"
  SYNC="${PATH_APP%% *}"
  [ "$ESC" = b0 ] && quitar_selector_residual

  if [ "$SYNC" = "Synced" ]; then
    if [ "$ESC" = b0 ]; then
      READY="$(kubectl -n "$NS" get deploy ms-orders -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
      # Con "set -e" y "pipefail", un "kubectl get" que no encuentra el Rollout abortaría el script
      if kubectl -n "$NS" get rollout ms-orders >/dev/null 2>&1; then ROLLOUT=1; else ROLLOUT=0; fi
      [ "${READY:-0}" = "2" ] && [ "$ROLLOUT" = "0" ] && break
    else
      FASE="$(kubectl -n "$NS" get rollout ms-orders -o jsonpath='{.status.phase}' 2>/dev/null || true)"
      [ "$FASE" = "Healthy" ] && break
    fi
  fi
  [ "$i" = 90 ] && { echo "Tiempo agotado esperando el escenario ${ESC}" >&2; exit 1; }
done

echo "Escenario ${ESC} activo."
kubectl -n argocd get application tfm --no-headers
kubectl -n "$NS" get deploy,rollout -l app=ms-orders --no-headers 2>/dev/null || true
kubectl -n "$NS" get pods -l app=ms-orders --no-headers
