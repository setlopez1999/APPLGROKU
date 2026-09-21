#!/bin/sh
# Ciclo completo: empaquetar → instalar en el simulador/Roku → lanzar y capturar la consola.
HOST=${HOST:-127.0.0.1}
SECS=${SECS:-12}
npx bsc --project bsconfig.json > /dev/null 2>&1 || { echo "FALLO al empaquetar"; exit 1; }
curl.exe -s -f -u rokudev:rokudev --digest -F "mysubmit=Install" -F "archive=@out/applg-roku.zip" "http://$HOST/plugin_install" 2>&1 | grep -oiE "Install Success|Compilation Failed|Install Failure[^<]*" | head -2
node scripts/dev-run.js "$SECS" "$HOST"
