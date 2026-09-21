#!/bin/sh
# Ciclo completo para un ISP: generar marca → empaquetar → instalar → lanzar y volcar la consola.
#
# Es el equivalente de cambiar de product flavor en el proyecto Kotlin: toda la identidad del
# cliente sale de brands/<isp>/ y no hay nada que tocar en el código.
#
#   sh scripts/dev-cycle.sh                                    oneplay en el simulador local
#   HOST=192.168.0.203 PASS=xxxx sh scripts/dev-cycle.sh        oneplay en un Roku real
#   HOST=192.168.0.203 PASS=xxxx sh scripts/dev-cycle.sh playcom
#
# Variables: HOST (ip del Roku), PASS (contraseña de desarrollador), SECS (segundos de consola)

ISP=${1:-oneplay}
HOST=${HOST:-127.0.0.1}
PASS=${PASS:-rokudev}
SECS=${SECS:-12}

echo "  ISP=$ISP  HOST=$HOST"

node scripts/build-isp.js "$ISP" || exit 1

npx bsc --project bsconfig.json > /dev/null 2>&1 || { echo "  FALLO al empaquetar"; exit 1; }

curl.exe -s -f -u "rokudev:$PASS" --digest \
  -F "mysubmit=Install" -F "archive=@out/applg-roku.zip" \
  "http://$HOST/plugin_install" 2>&1 | grep -oiE "Install Success|Compilation Failed|Install Failure" | head -1

node scripts/dev-run.js "$SECS" "$HOST"
