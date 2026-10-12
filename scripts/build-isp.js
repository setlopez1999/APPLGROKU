#!/usr/bin/env node
/**
 * Aplica la marca de un cliente al canal. Equivalente Roku del bloque de marca del
 * `build.gradle.kts` del proyecto Kotlin.
 *
 * ESQUEMA ENV — copiado del rediseño Kotlin a propósito: mismo nombre de archivo, mismo formato y
 * MISMAS CLAVES, para que quien configure un cliente allí sepa hacerlo aquí sin aprender nada nuevo.
 *
 *     ENV/config.txt        el cliente ACTIVO (properties: appname, badge, accent, baseUrl…)
 *     ENV/logo.png          logo interno (navbar y login), horizontal y transparente
 *     ENV/icon.png          icono del canal
 *     ENV/intro.png         fondo del intro
 *     ENV/login.png         fondo del login
 *
 * Diferencia con el Kotlin: allí `ENV/` es una sola carpeta que se edita a mano por cliente. Aquí
 * se guarda un catálogo en `brands/<isp>/` y el build COPIA el elegido a `ENV/`, para poder
 * alternar entre ISPs con un comando sin perder la configuración del otro.
 *
 *   node scripts/build-isp.js oneplay     copia brands/oneplay → ENV/ y aplica
 *   node scripts/build-isp.js             aplica lo que ya haya en ENV/
 */

const fs = require('fs');
const path = require('path');
const { readProperties, brandValue, brandBool } = require('./lib/properties');
const { solidPng, hexToRgb } = require('./lib/png');
const { decodePng, logoOnBackground, verticalFadePng } = require('./lib/image');

const ROOT = path.resolve(__dirname, '..');
const ENV = path.join(ROOT, 'ENV');
const isp = process.argv[2];

// ---- 1. seleccionar cliente ---------------------------------------------------

if (isp) {
  const origen = path.join(ROOT, 'brands', isp);
  if (!fs.existsSync(origen)) {
    console.error(`No existe brands/${isp}. Disponibles: ${listBrands().join(', ')}`);
    process.exit(1);
  }
  fs.mkdirSync(ENV, { recursive: true });
  for (const f of fs.readdirSync(origen)) {
    const from = path.join(origen, f);
    if (fs.statSync(from).isFile()) fs.copyFileSync(from, path.join(ENV, f));
  }
}

const cfg = readProperties(path.join(ENV, 'config.txt'));
if (Object.keys(cfg).length === 0) {
  console.error('ENV/config.txt vacío o inexistente. Usa: node scripts/build-isp.js <isp>');
  process.exit(1);
}

const appname = brandValue(cfg, 'appname', 'TV');
const accent = brandValue(cfg, 'accent', '#00BB5F');
const version = brandValue(cfg, 'version', '1.0.0');
const [major, minor, build] = version.split('.');

if (!/^#[0-9a-fA-F]{6}$/.test(accent)) {
  console.error(`accent debe ser "#RRGGBB", recibido: ${accent}`);
  process.exit(1);
}

// La versión se escribe en UN SOLO SITIO (config.txt) y de ahí sale todo: lo que ve el usuario en
// el perfil, el manifest y el número interno. Escribir el número aparte lo desincroniza en cuanto
// alguien olvida cambiar uno de los dos.
if (!/^\d+\.\d+\.\d+$/.test(version)) {
  console.error(`version debe ser "mayor.menor.parche", recibido: ${version}`);
  process.exit(1);
}

// EL RIESGO REAL DEL ESQUEMA: el número interno sale de quitar los puntos (1.0.1 -> 101), así que
// solo crece mientras ningún tramo pase de 9. Con un 1.0.10 el número sería 1010, y a partir de
// ahí 1.1.0 daría 110 y 2.0.0 daría 200 — ambos MENORES, o sea imposibles de publicar. Un número
// de versión quemado no se puede corregir, así que esto se detiene antes de empaquetar.
for (const tramo of [major, minor, build]) {
  if (Number(tramo) > 9) {
    console.error(
      `version ${version}: ningún tramo puede pasar de 9 con este esquema (el número interno ` +
        `quitaría los puntos y dejaría de crecer). Migrar a mayor*10000 + menor*100 + parche.`
    );
    process.exit(1);
  }
}
const versionCode = `${Number(major)}${Number(minor)}${Number(build)}`;

// Acento para TEXTO: el de marca mezclado un 35% hacia el blanco. La derivación va aquí y no en el
// canal porque es una cuenta fija: cuantos menos valores tenga que rellenar el ISP, menos formas
// hay de entregar una app mal configurada (06-MULTI-ISP del rediseño).
const accentText = '0x' + mixToWhite(accent, 0.35);

function mixToWhite(hex, amount) {
  const [r, g, b] = hexToRgb(hex);
  const mix = (c) => Math.round(c + (255 - c) * amount);
  return [mix(r), mix(g), mix(b)]
    .map((c) => c.toString(16).padStart(2, '0').toUpperCase())
    .join('');
}

// El backend concatena las rutas sin barra inicial, así que la base TIENE que acabar en "/".
// Sin esto, "https://isp.tv" + "api/get-web2" da "https://isp.tvapi/get-web2" y el login falla con
// un error de red que parece del servidor.
let baseUrl = brandValue(cfg, 'baseUrl', '');
if (baseUrl && !baseUrl.endsWith('/')) {
  console.warn(`  aviso: baseUrl no acababa en "/" — se añade (${baseUrl}/)`);
  baseUrl += '/';
}

// ---- 2. manifest --------------------------------------------------------------

write(
  path.join(ROOT, 'src', 'manifest'),
  fs
    .readFileSync(path.join(ROOT, 'scripts', 'manifest.tmpl'), 'utf8')
    .replace(/{{name}}/g, appname)
    .replace(/{{major}}/g, major || '1')
    .replace(/{{minor}}/g, minor || '0')
    .replace(/{{build}}/g, build || '0')
    .replace(/{{splashColor}}/g, brandValue(cfg, 'splashColor', '#0B0B0D'))
);

// ---- 3. imágenes --------------------------------------------------------------
// Las del cliente se copian con el nombre que espera el canal. Las que falten se rellenan con un
// placeholder liso, para que el paquete sea siempre instalable aunque el ISP no haya entregado el
// arte. Si falta el LOGO no se inventa nada: la app cae al nombre en texto (ver §4).

const imagesDst = path.join(ROOT, 'src', 'images');
fs.mkdirSync(imagesDst, { recursive: true });

const DESDE_ENV = {
  'logo.png': 'brand_logo.png',
  'icon.png': 'icon_focus_hd.png',
  'intro.png': 'brand_intro.png',
  'login.png': 'brand_login.png',
};

let hayLogo = false;
for (const [src, dst] of Object.entries(DESDE_ENV)) {
  const from = path.join(ENV, src);
  if (fs.existsSync(from)) {
    fs.copyFileSync(from, path.join(imagesDst, dst));
    if (src === 'logo.png') hayLogo = true;
  }
}

const oscuro = hexToRgb('#0B0B0D');

// TAMANOS EXACTOS QUE PIDE ROKU. Verificados contra la documentacion del manifest:
//   mm_icon_focus_fhd  540x405   obligatorio
//   mm_icon_focus_hd   290x218   obligatorio
//   mm_icon_focus_sd             obsoleto, ya no se genera
//   splash             1920x1080 / 1280x720 / 720x480
// Los valores anteriores (336x210 y 248x140) no correspondian a ninguna clave real.
const DERIVADAS = [
  { file: 'icon_focus_fhd.png', w: 540, h: 405, cover: 0.78 },
  { file: 'icon_focus_hd.png', w: 290, h: 218, cover: 0.78 },
  { file: 'splash_fhd.png', w: 1920, h: 1080, cover: 0.34 },
  { file: 'splash_hd.png', w: 1280, h: 720, cover: 0.34 },
  { file: 'splash_sd.png', w: 720, h: 480, cover: 0.34 },
  { file: 'brand_intro.png', w: 1280, h: 720, cover: 0.3 },
  { file: 'brand_login.png', w: 1280, h: 720, cover: 0.3 },
];

// El icono del canal salia un CUADRADO DE COLOR en la pantalla de inicio del Roku: sin poder leer
// el PNG del ISP, lo unico que se podia generar era un relleno liso. Ahora se compone el logo del
// cliente sobre el fondo de marca, que es ademas lo que hacen los otros clientes de la flota.
let logo = null;
if (hayLogo) {
  try {
    logo = decodePng(fs.readFileSync(path.join(ENV, 'logo.png')));
  } catch (err) {
    console.warn(`  aviso: no se pudo leer logo.png (${err.message}) — iconos en color liso`);
  }
}

const generadas = [];
for (const img of DERIVADAS) {
  const destino = path.join(imagesDst, img.file);
  // Lo que entregue el ISP manda: estas solo rellenan lo que falta.
  if (fs.existsSync(destino)) continue;

  if (logo) {
    fs.writeFileSync(destino, logoOnBackground(logo, img.w, img.h, oscuro, img.cover));
  } else {
    // Sin logo no hay nada que componer. Fondo de marca liso, nunca el color de acento a pantalla
    // completa: un bloque verde se lee como un error de carga.
    fs.writeFileSync(destino, solidPng(img.w, img.h, oscuro));
  }
  generadas.push(img.file);
}

// Degradados del overlay, como PNG de una fila por pixel. Antes se imitaban apilando rectangulos
// con alfa escalonada y en el aparato se veian A BANDAS (docs/DISENO.md 1).
const FADES = [
  { file: 'fade_header.png', h: 538, from: 0.88, to: 0.35 },
  { file: 'fade_epg.png', h: 160, from: 0.35, to: 1.0 },
];
for (const f of FADES) {
  fs.writeFileSync(path.join(imagesDst, f.file), verticalFadePng(f.h, [0, 0, 0], f.from, f.to));
}

// ---- 4. BrandConfig.brs -------------------------------------------------------
// Fuente ÚNICA de marca en runtime. Réplica de BrandConfig.kt: solo `accent` cambia por ISP, los
// neutros son fijos. Ver docs/DISENO.md §1.

const logoUri = hayLogo ? 'pkg:/images/brand_logo.png' : '';

const config = `' GENERADO por scripts/build-isp.js desde ENV/config.txt — NO EDITAR A MANO.
' Fuente unica de marca en runtime. Ver docs/DISENO.md y docs/MULTI_ISP.md.

function BrandConfig() as object
    if m.__brandConfig <> invalid then return m.__brandConfig

    accent = "${accent}"

    m.__brandConfig = {
        ' ---- Identidad (ENV/config.txt) ----
        appName: "${appname}"
        appBadge: "${brandValue(cfg, 'badge', '')}"
        appVersion: "${version}"
        ' Numero interno derivado, NUNCA escrito a mano: ver la validacion en build-isp.js.
        versionCode: ${versionCode}

        ' ---- Backend (ENV/config.txt) ----
        baseUrl: "${baseUrl}"
        notificationsUrl: "${brandValue(cfg, 'notificationsUrl', '')}"
        notificationsEnabled: ${brandBool(cfg, 'notificationsEnabled')}
        isCatchupClient: ${brandBool(cfg, 'isCatchupClient')}

        ' Plataforma del backend: 12 = Roku. Fijo, no cambia por ISP.
        ' (verificado en app-lg/src/js/login.js:13 — enum OS)
        platform: 12

        ' ---- Pestanas (switch maestro; se combina con lo que mande el backend) ----
        tabHomeEnabled: ${brandBool(cfg, 'tabHome')}
        tabEventsEnabled: ${brandBool(cfg, 'tabEvents')}
        tabContentEnabled: ${brandBool(cfg, 'tabContent')}

        ' ---- Imagenes ----
        ' Si el ISP no entrego logo, va vacio y la app cae al NOMBRE en texto con estilo de marca,
        ' igual que el rediseno Kotlin. Nunca se dibuja un rectangulo de color haciendo de logo.
        logoUri: "${logoUri}"
        introUri: "pkg:/images/brand_intro.png"
        loginUri: "pkg:/images/brand_login.png"

        ' ---- Formas redondeadas (9-patch blanco, se tine con blendColor) ----
        shapeCard: "pkg:/images/shape_card.9.png"
        shapePill: "pkg:/images/shape_pill.9.png"

        ' ---- Color de marca (unico que cambia por ISP) ----
        ' SceneGraph usa 0xRRGGBBAA; config.txt lo trae como #RRGGBB.
        accent: "0x" + hexOf(accent) + "FF"
        accentSoft: "0x" + hexOf(accent) + "33"

        ' Acento para TEXTO: el mismo color mezclado un 35% hacia el blanco. Existe por un problema
        ' real de contraste — un color de marca oscuro no se lee sobre las superficies grises del
        ' tema, y uno claro sí. Aclararlo por calculo lo deja legible CON CUALQUIER color de marca,
        ' sin tener que ajustar nada por ISP (06-MULTI-ISP del rediseno).
        accentText: "${accentText}FF"

        ' ---- Neutros del tema oscuro (NO cambian por cliente) ----
        background: "0x0B0B0DFF"
        surface: "0x161619FF"
        surfaceVariant: "0x1F1F23FF"
        textPrimary: "0xF5F5F7FF"
        textSecondary: "0x9BA1A6FF"
        textDisabled: "0x5A5F66FF"
        pillActive: "0xF5F5F7FF"
        pillActiveText: "0x0B0B0DFF"
        liveNow: "0xE53935FF"

        ' ---- Foco: BLANCO fijo en toda la app, no depende del color de marca ----
        focusOutline: "0xFFFFFFFF"
        focusBorderWidth: 6

        ' ---- Controles "glass" (un solo switch para toda la app) ----
        glassControls: true
        glassAlpha: 0.45
        controlSurface: "0x161619" + "72"
        controlSurfaceDisabled: "0x161619" + "4C"

        ' ---- Formas (px de 1920x1080; equivalen a los dp del Kotlin x2) ----
        cardRadius: 24
        pillRadius: 48
    }
    return m.__brandConfig
end function

' "#RRGGBB" -> "RRGGBB"
function hexOf(color as string) as string
    if Left(color, 1) = "#" then return Mid(color, 2)
    return color
end function
`;

write(path.join(ROOT, 'src', 'source', 'config', 'BrandConfig.brs'), config);

// ---- resumen ------------------------------------------------------------------

console.log(`\n  cliente: ${appname}${isp ? ` (brands/${isp})` : ' (ENV/)'}  v${version}`);
console.log(`  backend: ${brandValue(cfg, 'baseUrl', '(sin definir)')}`);
console.log(`  acento:  ${accent}`);
console.log(`  logo:    ${hayLogo ? 'del cliente' : 'NO entregado → la app usa el nombre en texto'}`);
if (generadas.length) console.log(`  placeholders: ${generadas.join(', ')}`);
console.log('');

// ---- helpers ------------------------------------------------------------------

function listBrands() {
  const dir = path.join(ROOT, 'brands');
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir).filter((f) => fs.statSync(path.join(dir, f)).isDirectory());
}

function write(file, content) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, content, 'utf8');
}
