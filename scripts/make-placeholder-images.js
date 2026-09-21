#!/usr/bin/env node
/**
 * Genera las 8 imágenes de marca como PNG de color sólido, para poder empaquetar y probar el canal
 * antes de que el ISP entregue el arte definitivo.
 *
 * Son PLACEHOLDERS: usan el color de marca de brand.json y llevan los tamaños exactos que pide
 * Roku (docs/MULTI_ISP.md §2). Sirven para sideload y para ver el canal en el aparato; para
 * publicar hay que sustituirlas por las de verdad.
 *
 * Uso:  node scripts/make-placeholder-images.js <isp>
 */

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const ROOT = path.resolve(__dirname, '..');
let CRC_TABLE = null;
const isp = process.argv[2] || 'oneplay';

const brandDir = path.join(ROOT, 'brands', isp);
if (!fs.existsSync(brandDir)) {
  console.error(`No existe brands/${isp}`);
  process.exit(1);
}

const brand = JSON.parse(fs.readFileSync(path.join(brandDir, 'brand.json'), 'utf8'));
const accent = hexToRgb(brand.accent || '#2ECC71');
const dark = hexToRgb('#0B0B0D'); // el neutro fijo del tema (DISENO §1)

// Tamaños exigidos por Roku + los fondos internos de la app.
const IMAGES = [
  { file: 'icon_focus_hd.png', w: 336, h: 210, color: accent },
  { file: 'icon_focus_sd.png', w: 248, h: 140, color: accent },
  { file: 'splash_fhd.png', w: 1920, h: 1080, color: dark },
  { file: 'splash_hd.png', w: 1280, h: 720, color: dark },
  { file: 'splash_sd.png', w: 720, h: 480, color: dark },
  { file: 'brand_logo.png', w: 360, h: 120, color: accent },
  { file: 'brand_intro.png', w: 1920, h: 1080, color: dark },
  { file: 'brand_login.png', w: 1920, h: 1080, color: dark },
];

const outDir = path.join(brandDir, 'images');
fs.mkdirSync(outDir, { recursive: true });

for (const img of IMAGES) {
  fs.writeFileSync(path.join(outDir, img.file), makePng(img.w, img.h, img.color));
  console.log(`  ${img.file.padEnd(22)} ${img.w}x${img.h}`);
}

console.log(`\n  8 placeholders en brands/${isp}/images/`);
console.log(`  Son provisionales: sustituir por el arte real antes de publicar.\n`);

// ---- PNG mínimo (color sólido) ----------------------------------------------

function makePng(width, height, [r, g, b]) {
  // Cada línea lleva delante un byte de filtro (0 = sin filtro).
  const raw = Buffer.alloc(height * (1 + width * 3));
  let pos = 0;
  for (let y = 0; y < height; y++) {
    raw[pos++] = 0;
    for (let x = 0; x < width; x++) {
      raw[pos++] = r;
      raw[pos++] = g;
      raw[pos++] = b;
    }
  }

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // 8 bits por canal
  ihdr[9] = 2; // color type 2 = RGB
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;

  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body), 0);
  return Buffer.concat([len, body, crc]);
}


function crc32(buf) {
  if (!CRC_TABLE) {
    CRC_TABLE = new Int32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      CRC_TABLE[n] = c;
    }
  }
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function hexToRgb(hex) {
  const clean = hex.replace('#', '');
  return [parseInt(clean.slice(0, 2), 16), parseInt(clean.slice(2, 4), 16), parseInt(clean.slice(4, 6), 16)];
}
