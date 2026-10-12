/**
 * Lectura y composición de imágenes, sin dependencias.
 *
 * Existe por dos problemas concretos que se vieron en un Roku Express real:
 *
 *   1. El ICONO del canal salía un CUADRADO DE COLOR en la pantalla de inicio del Roku. El
 *      generador solo sabía escribir rellenos lisos, así que cuando el ISP no entregaba `icon.png`
 *      rellenaba con el color de marca. Para componer el logo del cliente hay que poder LEER su
 *      PNG, y eso es lo que falta aquí.
 *
 *   2. Los degradados del overlay se veían A BANDAS. Estaban imitados apilando rectángulos con
 *      alfa escalonada —SceneGraph no tiene degradados— y cada rectángulo es un salto de opacidad
 *      visible sobre el vídeo. Con un PNG de una fila por píxel el salto es de 1/255 y desaparece.
 *
 * `zlib` es de Node, así que decodificar un PNG no añade ninguna dependencia: lo único que hay que
 * escribir a mano es el deshacer los filtros por fila, que son cinco y están en el estándar.
 */

const zlib = require('zlib');
const { encode } = require('./png');

/** PNG → { width, height, data } con `data` en RGBA de 8 bits. */
function decodePng(buf) {
  if (buf.readUInt32BE(0) !== 0x89504e47) throw new Error('no es un PNG');

  let width = 0;
  let height = 0;
  let colorType = 0;
  let palette = null;
  let trns = null;
  const idat = [];

  for (let p = 8; p + 8 <= buf.length; ) {
    const len = buf.readUInt32BE(p);
    const type = buf.toString('ascii', p + 4, p + 8);
    const data = buf.slice(p + 8, p + 8 + len);

    if (type === 'IHDR') {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      colorType = data[9];
      if (data[8] !== 8) throw new Error(`PNG de ${data[8]} bits por canal: solo se admiten 8`);
      if (data[12] !== 0) throw new Error('PNG entrelazado: hay que guardarlo sin entrelazar');
    } else if (type === 'PLTE') palette = data;
    else if (type === 'tRNS') trns = data;
    else if (type === 'IDAT') idat.push(data);
    else if (type === 'IEND') break;

    p += 12 + len;
  }

  const CHANNELS = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 };
  const ch = CHANNELS[colorType];
  if (ch === undefined) throw new Error(`tipo de color PNG no soportado: ${colorType}`);

  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = width * ch;
  const flat = Buffer.alloc(height * stride);

  // Deshacer los filtros por fila: los cinco del estándar.
  for (let y = 0; y < height; y++) {
    const rowStart = y * (stride + 1);
    const filter = raw[rowStart];
    for (let i = 0; i < stride; i++) {
      const left = i >= ch ? flat[y * stride + i - ch] : 0;
      const up = y > 0 ? flat[(y - 1) * stride + i] : 0;
      const upLeft = y > 0 && i >= ch ? flat[(y - 1) * stride + i - ch] : 0;

      let v = raw[rowStart + 1 + i];
      if (filter === 1) v += left;
      else if (filter === 2) v += up;
      else if (filter === 3) v += (left + up) >> 1;
      else if (filter === 4) v += paeth(left, up, upLeft);
      flat[y * stride + i] = v & 0xff;
    }
  }

  // Normalizar a RGBA: el resto del generador solo maneja eso.
  const data = Buffer.alloc(width * height * 4);
  for (let i = 0, o = 0; i < width * height; i++, o += 4) {
    if (colorType === 6) {
      flat.copy(data, o, i * 4, i * 4 + 4);
    } else if (colorType === 2) {
      data[o] = flat[i * 3];
      data[o + 1] = flat[i * 3 + 1];
      data[o + 2] = flat[i * 3 + 2];
      data[o + 3] = 255;
    } else if (colorType === 0) {
      data[o] = data[o + 1] = data[o + 2] = flat[i];
      data[o + 3] = 255;
    } else if (colorType === 4) {
      data[o] = data[o + 1] = data[o + 2] = flat[i * 2];
      data[o + 3] = flat[i * 2 + 1];
    } else {
      const idx = flat[i];
      data[o] = palette ? palette[idx * 3] : 0;
      data[o + 1] = palette ? palette[idx * 3 + 1] : 0;
      data[o + 2] = palette ? palette[idx * 3 + 2] : 0;
      data[o + 3] = trns && idx < trns.length ? trns[idx] : 255;
    }
  }

  return { width, height, data };
}

function paeth(a, b, c) {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  return pb <= pc ? b : c;
}

/**
 * Reducción por MEDIA DE ÁREA.
 *
 * No por muestreo simple: un logo de 1900 px bajado a 540 cogiendo un píxel de cada N sale dentado
 * y con el texto ilegible, y en el icono del canal eso se ve a dos metros. Se premultiplica el
 * alfa antes de promediar, o los bordes del logo transparente arrastran color de la nada.
 */
function boxResize(img, dstW, dstH) {
  const out = Buffer.alloc(dstW * dstH * 4);
  const sx = img.width / dstW;
  const sy = img.height / dstH;

  for (let y = 0; y < dstH; y++) {
    const y0 = Math.floor(y * sy);
    const y1 = Math.min(img.height, Math.max(y0 + 1, Math.floor((y + 1) * sy)));
    for (let x = 0; x < dstW; x++) {
      const x0 = Math.floor(x * sx);
      const x1 = Math.min(img.width, Math.max(x0 + 1, Math.floor((x + 1) * sx)));

      let r = 0;
      let g = 0;
      let b = 0;
      let a = 0;
      let n = 0;
      for (let yy = y0; yy < y1; yy++) {
        for (let xx = x0; xx < x1; xx++) {
          const i = (yy * img.width + xx) * 4;
          const al = img.data[i + 3] / 255;
          r += img.data[i] * al;
          g += img.data[i + 1] * al;
          b += img.data[i + 2] * al;
          a += img.data[i + 3];
          n++;
        }
      }
      if (n === 0) n = 1;

      const o = (y * dstW + x) * 4;
      const meanAlpha = a / n / 255;
      out[o] = meanAlpha > 0 ? Math.min(255, Math.round(r / n / meanAlpha)) : 0;
      out[o + 1] = meanAlpha > 0 ? Math.min(255, Math.round(g / n / meanAlpha)) : 0;
      out[o + 2] = meanAlpha > 0 ? Math.min(255, Math.round(b / n / meanAlpha)) : 0;
      out[o + 3] = Math.round(a / n);
    }
  }
  return { width: dstW, height: dstH, data: out };
}

/**
 * Logo centrado sobre un fondo liso, encajado sin deformarlo.
 *
 * `coverage` es la fracción del lienzo que ocupa el logo. Se deja un respiro alrededor porque en
 * la tira de iconos de la pantalla de inicio del Roku los iconos se recortan y se escalan, y un
 * logo pegado al borde se come.
 */
function logoOnBackground(logo, width, height, [bgR, bgG, bgB], coverage = 0.8) {
  const scale = Math.min((width * coverage) / logo.width, (height * coverage) / logo.height);
  const dstW = Math.max(1, Math.round(logo.width * scale));
  const dstH = Math.max(1, Math.round(logo.height * scale));
  const offX = Math.round((width - dstW) / 2);
  const offY = Math.round((height - dstH) / 2);
  const small = boxResize(logo, dstW, dstH);

  return encode(width, height, (x, y) => {
    const lx = x - offX;
    const ly = y - offY;
    if (lx < 0 || ly < 0 || lx >= dstW || ly >= dstH) return [bgR, bgG, bgB, 255];

    const i = (ly * dstW + lx) * 4;
    const a = small.data[i + 3] / 255;
    return [
      Math.round(small.data[i] * a + bgR * (1 - a)),
      Math.round(small.data[i + 1] * a + bgG * (1 - a)),
      Math.round(small.data[i + 2] * a + bgB * (1 - a)),
      255,
    ];
  });
}

/**
 * Degradado vertical de verdad: UNA FILA DE PÍXELES POR FILA DE PANTALLA.
 *
 * Reemplaza al apilado de rectángulos con alfa escalonada. Aquel truco se ve a BANDAS en el
 * aparato, porque cada rectángulo es un escalón de opacidad sobre el vídeo; aquí el escalón es de
 * 1/255 y no se distingue.
 *
 * Sale de 2 px de ancho a propósito: el `Poster` lo estira a 1920 y el escalado del aparato es
 * bilineal, así que horizontalmente queda plano sin coste de memoria. 2 y no 1 porque algunas
 * texturas de un solo píxel de ancho dan problemas de muestreo en los Roku de gama baja.
 */
function verticalFadePng(height, [r, g, b], alphaTop, alphaBottom) {
  return encode(2, height, (x, y) => {
    const t = height <= 1 ? 0 : y / (height - 1);
    const alpha = alphaTop + (alphaBottom - alphaTop) * t;
    return [r, g, b, Math.max(0, Math.min(255, Math.round(alpha * 255)))];
  });
}

/**
 * Degradado por PARADAS, vertical u horizontal.
 *
 * El del EPG en el rediseno NO es lineal: se queda claro hasta el 35% y despues oscurece deprisa
 * (0.30 / 0.60 / 0.88 / 1.0). Un degradado lineal entre los mismos extremos tapa el video mucho
 * antes y la pantalla se ve mas cerrada de lo que debe.
 *
 * `stops` es [[posicion 0..1, alfa 0..1], ...] en orden.
 */
function stopsFadePng(length, [r, g, b], stops, horizontal = false) {
  const alphaAt = (t) => {
    if (t <= stops[0][0]) return stops[0][1];
    for (let i = 1; i < stops.length; i++) {
      if (t <= stops[i][0]) {
        const [p0, a0] = stops[i - 1];
        const [p1, a1] = stops[i];
        const k = p1 === p0 ? 0 : (t - p0) / (p1 - p0);
        return a0 + (a1 - a0) * k;
      }
    }
    return stops[stops.length - 1][1];
  };

  const w = horizontal ? length : 2;
  const h = horizontal ? 2 : length;

  return encode(w, h, (x, y) => {
    const i = horizontal ? x : y;
    const t = length <= 1 ? 0 : i / (length - 1);
    return [r, g, b, Math.max(0, Math.min(255, Math.round(alphaAt(t) * 255)))];
  });
}

module.exports = { decodePng, boxResize, logoOnBackground, verticalFadePng, stopsFadePng };
