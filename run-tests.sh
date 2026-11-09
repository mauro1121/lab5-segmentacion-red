#!/usr/bin/env bash
# ============================================================
# Ejecuta las 5 pruebas en la estructura antes/ y despues/.
# Uso (Linux/macOS):
#   ./run-tests.sh antes
#   ./run-tests.sh despues
# En Windows usa los comandos del README directamente en PowerShell.
# ============================================================
set -u
DIR="${1:-despues}"
if [ "$DIR" != "antes" ] && [ "$DIR" != "despues" ]; then
  echo "Uso: ./run-tests.sh [antes|despues]"; exit 1
fi

cd "$(dirname "$0")/$DIR" || exit 1
echo "============================================================"
echo " Escenario: $DIR"
echo "============================================================"
echo "[*] Levantando servicios..."
docker compose up -d --build
echo "[*] Esperando a que la db acepte conexiones (10s)..."
sleep 10

run() { echo ""; echo ">>> PRUEBA $1: $2"; echo "    \$ $3"; eval "$3"; echo "    (exit: $?)"; }

run 1 "Exterior -> gateway"           "curl -s localhost; echo"
run 1b "Cadena completa (gw->be->db)" "curl -s localhost/api/health; echo"
run 2 "gateway -> backend"            "docker compose exec -T gateway curl -s backend:3000/health; echo"
run 3 "backend -> db"                 "docker compose exec -T backend nc -zv -w 3 db 5432"
run 4 "gateway -> db"                 "docker compose exec -T gateway nc -zv -w 3 db 5432"

if [ "$DIR" = "antes" ]; then
  run 5 "Exterior -> db (15432)"      "nc -zv -w 3 localhost 15432"
else
  run 5 "Exterior -> db (15432)"      "nc -zv -w 3 localhost 15432"
fi

echo ""
echo "[*] Para apagar:  (cd $DIR && docker compose down)"
