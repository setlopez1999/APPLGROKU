#!/usr/bin/env node
/**
 * Lanza el canal en el Roku (o en el simulador) y vuelca la consola de depuración.
 *
 * Se conecta ANTES de lanzar, porque los errores de arranque salen en el primer segundo y si te
 * conectas después ya te los has perdido.
 *
 * Uso:
 *   node scripts/dev-run.js [segundos] [host]
 *   node scripts/dev-run.js 12 127.0.0.1
 *   node scripts/dev-run.js 12 127.0.0.1 --no-launch   (solo escuchar)
 */

const net = require('net');

const seconds = parseInt(process.argv[2] || '12', 10);
const host = process.argv[3] || '127.0.0.1';
const noLaunch = process.argv.includes('--no-launch');

const CONSOLE_PORT = 8085;
const ECP_PORT = 8060;

const socket = net.createConnection(CONSOLE_PORT, host);
socket.setEncoding('utf8');

socket.on('connect', () => {
  console.log(`--- consola ${host}:${CONSOLE_PORT} conectada ---`);
  if (noLaunch) return;
  setTimeout(launch, 800);
});

socket.on('data', (chunk) => process.stdout.write(chunk));

socket.on('error', (err) => {
  console.error(`No se pudo abrir la consola (${host}:${CONSOLE_PORT}): ${err.message}`);
  process.exit(1);
});

async function launch() {
  try {
    const res = await fetch(`http://${host}:${ECP_PORT}/launch/dev`, { method: 'POST' });
    console.log(`--- launch/dev → HTTP ${res.status} ---`);
  } catch (err) {
    console.error(`--- no se pudo lanzar: ${err.message} ---`);
  }
}

setTimeout(() => {
  console.log('\n--- fin de la captura ---');
  socket.destroy();
  process.exit(0);
}, seconds * 1000);
