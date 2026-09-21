/**
 * Lector de ficheros `.properties`, el mismo formato que usa `ENV/config.txt` en el proyecto
 * Kotlin (`Properties().load(...)` de Java). Se replica para que la config del cliente sea
 * LITERALMENTE el mismo archivo en los dos proyectos: quien sepa configurar uno, sabe el otro.
 *
 * Soporta: `clave=valor`, comentarios con `#` o `!`, espacios alrededor, y líneas en blanco.
 */

const fs = require('fs');

function readProperties(file) {
  if (!fs.existsSync(file)) return {};

  const out = {};
  for (const raw of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('#') || line.startsWith('!')) continue;

    const i = line.indexOf('=');
    if (i < 0) continue;

    out[line.slice(0, i).trim()] = line.slice(i + 1).trim();
  }
  return out;
}

/** Igual que `brand(key, fallback)` del build.gradle.kts del Kotlin. */
function brandValue(props, key, fallback) {
  const v = props[key];
  return v === undefined || v === '' ? fallback : v;
}

function brandBool(props, key, fallback = false) {
  const v = brandValue(props, key, String(fallback)).trim().toLowerCase();
  return v === 'true' || v === '1';
}

module.exports = { readProperties, brandValue, brandBool };
