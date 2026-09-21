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
const RELLENO = [
  { file: 'icon_focus_hd.png', w: 336, h: 210, color: hexToRgb(accent) },
  { file: 'icon_focus_sd.png', w: 248, h: 140, color: hexToRgb(accent) },
  { file: 'splash_fhd.png', w: 1920, h: 1080, color: oscuro },
  { file: 'splash_hd.png', w: 1280, h: 720, color: oscuro },
  { file: 'splash_sd.png', w: 720, h: 480, color: oscuro },
  { file: 'brand_intro.png', w: 1280, h: 720, color: oscuro },
  { file: 'brand_login.png', w: 1280, h: 720, color: oscuro },
];

const generadas = [];
for (const img of RELLENO) {
  const destino = path.join(imagesDst, img.file);
  if (!fs.existsSync(destino)) {
    fs.writeFileSync(destino, solidPng(img.w, img.h, img.color));
    generadas.push(img.file);
  }
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

        ' ---- Backend (ENV/config.txt) ----
        baseUrl: "${brandValue(cfg, 'baseUrl', '')}"
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
