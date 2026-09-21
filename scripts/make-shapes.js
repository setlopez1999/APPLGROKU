#!/usr/bin/env node
/**
 * Genera las formas redondeadas de la interfaz como 9-patch.
 *
 * SceneGraph no sabe dibujar esquinas redondeadas: `Rectangle` solo hace esquinas rectas. La
 * solución en Roku es un `Poster` con una imagen 9-patch, que estira únicamente la franja central
 * y deja las esquinas intactas a cualquier tamaño.
 *
 * Se generan en BLANCO y se tiñen en runtime con `blendColor`, así que **dos texturas diminutas
 * cubren todos los colores de la app**. En un Roku Express, donde la memoria de texturas escasea,
 * eso es la diferencia entre 2 imágenes y una por cada combinación de color y radio.
 *
 * Los radios salen de los mismos tokens que usa el código (docs/DISENO.md §0):
 *   tarjeta  24 px   (12 dp del Kotlin ×2)
 *   píldora  48 px   (24 dp del Kotlin ×2)
 */

const fs = require('fs');
const path = require('path');
const { roundedNinePatch } = require('./lib/png');

const ROOT = path.resolve(__dirname, '..');
const destino = path.join(ROOT, 'src', 'images');
fs.mkdirSync(destino, { recursive: true });

const FORMAS = [
  { file: 'shape_card.9.png', radius: 24 },
  { file: 'shape_pill.9.png', radius: 48 },
];

for (const forma of FORMAS) {
  const buf = roundedNinePatch(forma.radius);
  fs.writeFileSync(path.join(destino, forma.file), buf);
  const lado = forma.radius * 2 + 3;
  console.log(`  ${forma.file.padEnd(20)} radio ${String(forma.radius).padStart(2)} px  ·  ${lado}x${lado}  ·  ${buf.length} bytes`);
}

console.log('\n  Se tiñen con blendColor: una textura por radio sirve para todos los colores.\n');
