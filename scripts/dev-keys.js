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

  for (const key of keys) {
    const res = await fetch(`http://${host}:${PORT}/keypress/${key}`, { method: 'POST' });
    const label = key.startsWith('Lit_') ? key : key.padEnd(8);
    process.stdout.write(`${label} ${res.status === 200 ? 'ok' : 'HTTP ' + res.status}  `);
    await sleep(DELAY_MS);
  }
  console.log('');
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

/** Solo los caracteres que romperían la ruta de la URL. El resto viaja tal cual. */
function escapeLiteral(ch) {
  const needsEscape = [' ', '#', '?', '%', '&', '+', '/', '\\'];
  return needsEscape.includes(ch) ? '%' + ch.charCodeAt(0).toString(16).toUpperCase().padStart(2, '0') : ch;
}
