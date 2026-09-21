#!/usr/bin/env node
/**
 * Manda teclas al Roku (o al simulador) por ECP, para poder recorrer la app sin tocar el mando.
 *
 * Uso:
 *   node scripts/dev-keys.js Down Down OK
 *   node scripts/dev-keys.js --text "demo@isp.tv"
 *   HOST=192.168.0.53 node scripts/dev-keys.js Back
 *
 * Teclas: Up Down Left Right Select OK Back Home Play Rev Fwd InstantReplay Info Backspace Enter
 */

const host = process.env.HOST || '127.0.0.1';
const PORT = 8060;
const DELAY_MS = 350; // en TV hay que dar tiempo a que el foco se asiente

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});

async function main() {
  const args = process.argv.slice(2);
  const keys = [];

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--text') {
      // Cada carácter viaja como Lit_<char>. Solo se escapa lo que rompería la URL:
      // percent-encodear de más hace que el carácter se pierda por el camino (verificado con la
      // arroba: `Lit_%40` no escribe nada, `Lit_@` sí).
      for (const ch of args[++i]) keys.push('Lit_' + escapeLiteral(ch));
    } else {
      keys.push(args[i] === 'OK' ? 'Select' : args[i]);
    }
  }

  let perdidas = 0;
  for (const key of keys) {
    const ok = await pressWithRetry(host, key);
    if (!ok) perdidas++;
    const label = key.startsWith('Lit_') ? key : key.padEnd(8);
    process.stdout.write(`${label} ${ok ? 'ok' : 'PERDIDA'}  `);
    await sleep(DELAY_MS);
  }
  console.log('');
  if (perdidas > 0) console.error(`  ${perdidas} tecla(s) perdidas: la secuencia NO es fiable`);
}

/**
 * Sobre WiFi, contra un Roku real, alguna petición ECP se pierde. Sin reintento la secuencia se
 * desincroniza y parece un bug de la app: perseguí un rato un "Back que no funciona" que en
 * realidad era una tecla que nunca salió de aquí (2026-09-21).
 */
async function pressWithRetry(host, key, intentos = 3) {
  for (let i = 0; i < intentos; i++) {
    try {
      const res = await fetch(`http://${host}:${PORT}/keypress/${key}`, { method: 'POST' });
      if (res.status === 200 || res.status === 202 || res.status === 204) return true;
    } catch (err) {
      // reintento
    }
    await sleep(200);
  }
  return false;
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

/**
 * Percent-encoding de todo lo que no sea alfanumérico, que es lo que documenta Roku para ECP.
 *
 * OJO, hay una diferencia entre aparato y simulador (verificada el 2026-09-21):
 *   Roku real   → `Lit_@` NO escribe nada; hay que mandar `Lit_%40`
 *   brs-desktop → al revés: `Lit_%40` no escribe nada y `Lit_@` sí
 * Manda el aparato real, así que se escapa. Si algún día hace falta teclear en el simulador, este
 * es el único sitio donde se cambia.
 */
function escapeLiteral(ch) {
  if (/[A-Za-z0-9]/.test(ch)) return ch;
  return '%' + ch.charCodeAt(0).toString(16).toUpperCase().padStart(2, '0');
}
