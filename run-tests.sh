#!/usr/bin/env bash
# ============================================================
# Laboratorio 5 - Ejecuta las 5 pruebas de la tabla.
# Uso:
#   ANTES (todo en una red):   ./run-tests.sh before
#   DESPUÉS (segmentado):      ./run-tests.sh after
# ============================================================
set -u
MODE="${1:-after}"

if [ "$MODE" = "before" ]; then
  FILE="docker-compose.before.yml"
else
  FILE="docker-compose.yml"
fi

DC="docker compose -f $FILE"

echo "============================================================"
echo " Escenario: $MODE   ($FILE)"
echo "============================================================"
echo "[*] Levantando servicios..."
$DC up -d --build
echo "[*] Esperando a que la db acepte conexiones (10s)..."
sleep 10

# nginx:alpine no trae nc ni curl -> se instalan solo para las pruebas.
echo "[*] Instalando curl/nc en el gateway solo para las pruebas..."
$DC exec -T gateway sh -c "command -v nc >/dev/null 2>&1 && command -v curl >/dev/null 2>&1 || (apk add --no-cache netcat-openbsd curl >/dev/null 2>&1)"

run() {
  echo ""
  echo ">>> PRUEBA $1: $2"
  echo "    \$ $3"
  eval "$3"
  echo "    (exit code: $?)"
}

run 1 "Exterior -> gateway"  "curl -s -o /dev/null -w '%{http_code}' localhost; echo"
run 2 "gateway -> backend"   "$DC exec -T gateway curl -s backend:3000/health; echo"
run 3 "backend -> db"        "$DC exec -T backend nc -zv db 5432"
run 4 "gateway -> db"        "$DC exec -T gateway nc -zv db 5432"
run 5 "Exterior -> db"       "nc -zv localhost 5432"

echo ""
echo "[*] Para apagar:  $DC down"
