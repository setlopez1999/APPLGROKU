/**
 * Escritor de PNG mínimo (sin dependencias) para los assets que el build genera.
 *
 * Dos usos:
 *   - `solidPng`   : rellenos lisos (splash, placeholders de marca).
 *   - `roundedNinePatch` : la forma redondeada de TODA la interfaz.
 *
 * Por qué un 9-patch y no un PNG por cada botón: SceneGraph **no sabe dibujar rectángulos con
 * esquinas redondeadas** — `Rectangle` solo hace esquinas rectas. La solución estándar en Roku es
 * un `Poster` con una imagen 9-patch, que estira solo la zona central y deja las esquinas intactas
 * a cualquier tamaño.
 *
 * Y se genera en BLANCO a propósito: el `Poster` lo tiñe con `blendColor`, así que **una sola
 * textura por radio** sirve para todos los colores de la app. En un Roku Express, donde la memoria
 * de texturas es escasa, eso importa: 2 texturas en vez de una por cada combinación color×radio.
 */

const zlib = require('zlib');

let CRC_TABLE = null;

/** PNG RGBA de color sólido. */
function solidPng(width, height, [r, g, b], a = 255) {
  return encode(width, height, (x, y) => [r, g, b, a]);
}

/**
 * 9-patch de rectángulo redondeado, blanco, con las esquinas suavizadas.
 *
 * El contenido mide (2R+1)² — el mínimo con el que un 9-patch conserva las esquinas — y va rodeado
 * del borde de 1 px que marca la zona estirable, tal como especifica el formato.
 */
function roundedNinePatch(radius) {
  const R = radius;
  const size = 2 * R + 1; // contenido
  const total = size + 2; // + borde de marcas

  return encode(total, total, (x, y) => {
    const enBorde = x === 0 || y === 0 || x === total - 1 || y === total - 1;

    if (enBorde) {
      // Marcas del 9-patch: negras sobre los bordes SUPERIOR e IZQUIERDO, señalando la fila y la
      // columna centrales, que son las únicas que se estiran. El resto del borde, transparente.
      const centro = 1 + R;
      const esMarcaSuperior = y === 0 && x === centro;
      const esMarcaIzquierda = x === 0 && y === centro;
      return esMarcaSuperior || esMarcaIzquierda ? [0, 0, 0, 255] : [0, 0, 0, 0];
    }

    // Distancia al centro del arco. Con un contenido de 2R+1 los cuatro centros coinciden en (R,R),
    // que es justo lo que hace que la forma se estire sin deformar las esquinas.
    const cx = x - 1;
    const cy = y - 1;
    const dx = cx < R ? R - cx : cx > R ? cx - R : 0;
    const dy = cy < R ? R - cy : cy > R ? cy - R : 0;
    const d = Math.sqrt(dx * dx + dy * dy);

    // Medio píxel de suavizado en el borde del arco: sin esto las esquinas se ven dentadas en una TV.
    const alpha = Math.max(0, Math.min(1, R + 0.5 - d));
    return [255, 255, 255, Math.round(alpha * 255)];
  });
}

// ---- codificación ------------------------------------------------------------

function encode(width, height, pixelAt) {
  const raw = Buffer.alloc(height * (1 + width * 4));
  let pos = 0;
  for (let y = 0; y < height; y++) {
    raw[pos++] = 0; // filtro "ninguno"
    for (let x = 0; x < width; x++) {
      const [r, g, b, a] = pixelAt(x, y);
      raw[pos++] = r;
      raw[pos++] = g;
      raw[pos++] = b;
      raw[pos++] = a;
    }
  }

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bits por canal
  ihdr[9] = 6; // color type 6 = RGBA

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
  const clean = String(hex).replace('#', '');
  return [parseInt(clean.slice(0, 2), 16), parseInt(clean.slice(2, 4), 16), parseInt(clean.slice(4, 6), 16)];
}

module.exports = { solidPng, roundedNinePatch, hexToRgb };
