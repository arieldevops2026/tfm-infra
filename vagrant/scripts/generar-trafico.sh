#!/usr/bin/env bash
# Genera tráfico continuo contra ms-orders a través de Traefik.
# Uso: ./generar-trafico.sh [peticiones_por_segundo]   (por defecto 5). Ctrl+C para parar.
set -u

URL="${URL:-http://192.168.56.20/api/v1/orders/create}"
RPS="${1:-5}"
PAUSA=$(awk "BEGIN {print 1/$RPS}")
BODY='{"data":{"customerId":"CUS-001","paymentMethod":"CARD","items":[{"productId":"PRD-001","quantity":1}]}}'

echo "Enviando ~${RPS} peticiones/s a ${URL} (Ctrl+C para parar)"
while true; do
  curl -s -m 5 -o /dev/null -X POST "$URL" \
    -H 'Content-Type: application/json' -d "$BODY" &
  sleep "$PAUSA"
done
