#!/usr/bin/env node
/**
 * Auditoría de reproducción, desde la terminal y sin tocar el Roku.
 *
 * Es el port del `StreamPlaybackAuditTest` del repo Kotlin, y `docs/BACKEND-GOTCHAS.md` §13 lo
 * señala como lo primero que conviene tener al arrancar en una plataforma nueva: convierte
 * "está en negro y no sé por qué" en una tabla con la causa exacta por canal.
 *
 * Un 200 NO basta. Para saber si un canal ENTREGA vídeo hay que recorrer la cadena entera, igual
 * que hace el reproductor:
 *   1. el manifiesto maestro responde y declara un códec de vídeo
 *   2. se resuelve la variante y su chunklist TIENE segmentos
 *   3. el primer segmento trae bytes y es MPEG-TS válido (0x47 cada 188)
 *
 * Límite honesto: verifica que el stream entrega vídeo decodificable, no que la pantalla lo pinte.
 * Que el decodificador del aparato acepte el formato solo se comprueba en el Roku.
 *
 * Uso:
 *   node scripts/audit-streams.js --host oneplay.iptvperu.tv --user X --pass Y [--limit 10] [--catchup]
 *   node scripts/audit-streams.js --url "https://host:1936/dir/canal.stream/playlist.m3u8"
 */

const UA = 'APPMOVIL-roku'; // sin esto, los servidores de Playcom devuelven 403 (§1)
const TS_PACKET = 188;
const TS_SYNC = 0x47;

const args = parseArgs(process.argv.slice(2));

main().catch((err) => {
  console.error('\n  Error inesperado:', err.message);
  process.exit(1);
});

async function main() {
  if (args.url) {
    const result = await auditStream(args.url, 'url suelta');
    printRows([result]);
    return;
  }

  if (!args.host || !args.user || !args.pass) {
    console.error(`
  Faltan datos. Uso:
    node scripts/audit-streams.js --host <host> --user <email> --pass <clave> [--limit N] [--catchup]
    node scripts/audit-streams.js --url <m3u8>
`);
    process.exit(1);
  }

  const base = args.host.startsWith('http') ? args.host : `https://${args.host}`;
  const loginUrl =
    `${base.replace(/\/$/, '')}/api/get-web2` +
    `?user=${encodeURIComponent(args.user)}` +
    `&pass=${encodeURIComponent(args.pass)}` +
    `&devid=audit1234&platform=12`; // 12 = Roku

  console.log(`\n  get-web2 → ${base}`);
  const res = await fetch(loginUrl, { method: 'POST', headers: { 'User-Agent': UA } });
  const json = await res.json();

  if (json.error) {
    console.error(`  El backend respondió error: ${json.message || '(sin mensaje)'}`);
    process.exit(1);
  }

  const channels = flatten(json);
  const withUrl = channels.filter((c) => c.url);
  console.log(
    `  ${json.user || '?'} · plan "${json.plan || '?'}" · ` +
      `${channels.length} canales, ${withUrl.length} con url (${channels.length - withUrl.length} fuera del plan)\n`
  );

  const limit = args.limit ? parseInt(args.limit, 10) : withUrl.length;
  const target = withUrl.slice(0, limit);

  const rows = [];
  for (const channel of target) {
    process.stdout.write(`  auditando ${channel.nombre}…`.padEnd(60) + '\r');
    const row = await auditStream(channel.url, channel.nombre);

    if (args.catchup && channel.catchup === 1) {
      row.dvr = await probeDvr(channel.url);
    } else if (args.catchup) {
      row.dvr = '—';
    }
    rows.push(row);
  }

  printRows(rows);
  printSummary(rows);
}

/** Recorre la cadena completa de un stream HLS. */
async function auditStream(url, name) {
  const row = { name, estado: '', detalle: '', codec: '', segmentos: '' };

  const master = await get(url);
  if (master.tls) {
    // No hay código HTTP: la conexión ni se establece. Certificado o SNI, NO señal caída (§8).
    row.estado = 'TLS';
    row.detalle = master.error;
    return row;
  }
  if (master.status !== 200) {
    row.estado = master.status === 404 ? '404' : `HTTP ${master.status}`;
    row.detalle = 'la ruta no existe o el stream no está publicado';
    return row;
  }

  let mediaUrl = url;
  let body = master.body;

  if (body.includes('#EXT-X-STREAM-INF')) {
    const variant = pickVariant(body, url);
    if (!variant) {
      row.estado = 'SIN VARIANTE';
      row.detalle = 'el maestro no lista ninguna variante';
      return row;
    }
    row.codec = variant.codecs || '?';
    mediaUrl = variant.url;

    const media = await get(mediaUrl);
    if (media.tls) {
      row.estado = 'TLS';
      row.detalle = media.error;
      return row;
    }
    if (media.status !== 200) {
      row.estado = `HTTP ${media.status}`;
      row.detalle = 'la variante no responde';
      return row;
    }
    body = media.body;
  }

  const segments = segmentUrls(body, mediaUrl);
  row.segmentos = String(segments.length);

  if (segments.length === 0) {
    // 200 con la chunklist VACÍA: el directorio tiene DVR o el canal existe, pero no entra nada.
    // Casi siempre la señal de origen está caída. Un chequeo por código HTTP no lo detecta (§4).
    row.estado = 'SIN SEGMENTOS';
    row.detalle = '200 pero la lista viene vacía (señal de origen caída)';
    return row;
  }

  const seg = await get(segments[0], true);
  if (seg.tls) {
    row.estado = 'TLS';
    row.detalle = seg.error;
    return row;
  }
  if (seg.status !== 200 || !seg.bytes || seg.bytes.length === 0) {
    row.estado = 'SEGMENTO VACÍO';
    row.detalle = `el primer segmento devolvió ${seg.status} sin bytes`;
    return row;
  }

  if (!isMpegTs(seg.bytes)) {
    row.estado = 'NO ES TS';
    row.detalle = `${seg.bytes.length} bytes, pero sin sincronismo MPEG-TS`;
    return row;
  }

  row.estado = 'OK';
  row.detalle = `${Math.round(seg.bytes.length / 1024)} KB de MPEG-TS válido`;
  return row;
}

/** Sonda del DVR. Es binario: si graba responde a cualquier rango, si no, 404 siempre (§4). */
async function probeDvr(liveUrl) {
  const start = Math.floor(Date.now() / 1000) - 600;
  const probe = `${liveUrl.split('.m3u8')[0]}_dvr_range-${start}-60.m3u8`;

  const res = await get(probe);
  if (res.tls) return 'TLS';
  if (res.status !== 200) return `no (${res.status})`;
  const segs = segmentUrls(res.body, probe);
  if (segs.length === 0) return 'vacío'; // el flag miente: dice catchup=1 pero no hay nada grabado
  return 'sí';
}

// ---- HTTP --------------------------------------------------------------------

async function get(url, binary = false) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 12000);
  try {
    const res = await fetch(url, {
      headers: { 'User-Agent': UA },
      signal: controller.signal,
      redirect: 'follow',
    });
    if (binary) {
      const buf = Buffer.from(await res.arrayBuffer());
      return { status: res.status, bytes: buf };
    }
    return { status: res.status, body: await res.text() };
  } catch (err) {
    const code = err.cause?.code || err.name || 'ERROR';
    return { tls: true, status: -1, error: describeTransportError(code) };
  } finally {
    clearTimeout(timer);
  }
}

function describeTransportError(code) {
  const map = {
    CERT_HAS_EXPIRED: 'certificado vencido en ese hostname (la señal puede estar perfecta)',
    UNABLE_TO_VERIFY_LEAF_SIGNATURE: 'cadena de certificados incompleta',
    ERR_TLS_CERT_ALTNAME_INVALID: 'el certificado no cubre ese hostname (SNI)',
    ENOTFOUND: 'el hostname no resuelve',
    ECONNREFUSED: 'conexión rechazada',
    ETIMEDOUT: 'tiempo de espera agotado',
    AbortError: 'tiempo de espera agotado',
  };
  return map[code] || code;
}

// ---- HLS ---------------------------------------------------------------------

function pickVariant(manifest, baseUrl) {
  const lines = manifest.split('\n').map((l) => l.trim());
  for (let i = 0; i < lines.length; i++) {
    if (!lines[i].startsWith('#EXT-X-STREAM-INF')) continue;
    const codecs = /CODECS="([^"]+)"/.exec(lines[i])?.[1];
    const resolution = /RESOLUTION=([0-9x]+)/.exec(lines[i])?.[1];
    const uri = lines.slice(i + 1).find((l) => l && !l.startsWith('#'));
    if (uri) {
      return {
        url: new URL(uri, baseUrl).toString(),
        codecs: [codecs, resolution].filter(Boolean).join(' '),
      };
    }
  }
  return null;
}

function segmentUrls(playlist, baseUrl) {
  return playlist
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith('#'))
    .map((l) => new URL(l, baseUrl).toString());
}

/** MPEG-TS válido: byte 0x47 al inicio de cada paquete de 188 bytes. */
function isMpegTs(buf) {
  if (buf.length < TS_PACKET * 2) return false;
  for (let i = 0; i < 5 && (i + 1) * TS_PACKET <= buf.length; i++) {
    if (buf[i * TS_PACKET] !== TS_SYNC) return false;
  }
  return true;
}

// ---- catálogo ----------------------------------------------------------------

/** Mismo aplanado que la app (categorías → secciones → canales). */
function flatten(json) {
  const out = [];
  for (const category of json.sections || []) {
    for (const section of category.sections || []) {
      for (const channel of section.canales || []) {
        out.push({
          nombre: channel.nombre || '?',
          url: channel.url || '',
          catchup: channel.catchup || 0,
          seccion: section.nombre || '?',
        });
      }
    }
  }
  return out;
}

// ---- salida ------------------------------------------------------------------

function printRows(rows) {
  const w = Math.min(28, Math.max(10, ...rows.map((r) => r.name.length)));
  const conDvr = rows.some((r) => r.dvr !== undefined);

  console.log('');
  console.log(
    '  ' +
      'CANAL'.padEnd(w) +
      '  ' +
      'ESTADO'.padEnd(15) +
      'SEGS'.padEnd(6) +
      (conDvr ? 'DVR'.padEnd(10) : '') +
      'DETALLE'
  );
  console.log('  ' + '-'.repeat(w + 23 + (conDvr ? 10 : 0) + 30));

  for (const r of rows) {
    console.log(
      '  ' +
        r.name.slice(0, w).padEnd(w) +
        '  ' +
        r.estado.padEnd(15) +
        String(r.segmentos || '').padEnd(6) +
        (conDvr ? String(r.dvr || '').padEnd(10) : '') +
        r.detalle
    );
  }
}

function printSummary(rows) {
  const ok = rows.filter((r) => r.estado === 'OK').length;
  const tls = rows.filter((r) => r.estado === 'TLS').length;
  console.log(`\n  ${ok}/${rows.length} canales entregan vídeo decodificable`);
  if (tls > 0) {
    console.log(`  ${tls} fallan por TLS — revisar certificado antes de culpar a la señal (§8)`);
  }
  console.log('');
}

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i].startsWith('--')) {
      const key = argv[i].slice(2);
      const next = argv[i + 1];
      if (!next || next.startsWith('--')) {
        out[key] = true;
      } else {
        out[key] = next;
        i++;
      }
    }
  }
  return out;
}
