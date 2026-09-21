#!/usr/bin/env node
/**
 * Genera el canal para un ISP concreto a partir de `brands/<isp>/`.
 *
 * Produce (y por eso estos tres están en .gitignore — la fuente de verdad es brands/):
 *   src/manifest
 *   src/source/config/BrandConfig.brs
 *   src/images/*            (copiadas de brands/<isp>/images/)
 *
 * Uso:  node scripts/build-isp.js <isp>
 * Ver:  docs/MULTI_ISP.md
 */

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const isp = process.argv[2];

if (!isp) {
  console.error('Uso: node scripts/build-isp.js <isp>\nISPs disponibles: ' + listBrands().join(', '));
  process.exit(1);
}

const brandDir = path.join(ROOT, 'brands', isp);
if (!fs.existsSync(brandDir)) {
  console.error(`No existe brands/${isp}. Disponibles: ` + listBrands().join(', '));
  process.exit(1);
}

const brand = JSON.parse(fs.readFileSync(path.join(brandDir, 'brand.json'), 'utf8'));
validate(brand);

const [major, minor, build] = String(brand.version).split('.');

// ---- manifest ----------------------------------------------------------------
const manifest = fs
  .readFileSync(path.join(ROOT, 'scripts', 'manifest.tmpl'), 'utf8')
  .replace(/{{name}}/g, brand.name)
  .replace(/{{major}}/g, major || '1')
  .replace(/{{minor}}/g, minor || '0')
  .replace(/{{build}}/g, build || '0')
  .replace(/{{splashColor}}/g, brand.splashColor || '#000000');

write(path.join(ROOT, 'src', 'manifest'), manifest);

// ---- BrandConfig.brs ---------------------------------------------------------
// Fuente única de marca en runtime. Réplica de BrandConfig.kt del rediseño Kotlin:
// solo `accent` cambia por ISP; los neutros son fijos (ver docs/DISENO.md §1).
const tabs = brand.tabs || {};
const config = `' GENERADO por scripts/build-isp.js desde brands/${isp}/brand.json — NO EDITAR A MANO.
' Fuente única de marca en runtime. Ver docs/DISENO.md y docs/MULTI_ISP.md.

function BrandConfig() as object
    if m.__brandConfig <> invalid then return m.__brandConfig

    accent = "${brand.accent}"

    m.__brandConfig = {
        ' ---- Identidad (por ISP) ----
        appName: "${brand.name}"
        appBadge: "${brand.badge || ''}"
        appVersion: "${brand.version}"

        ' ---- Backend (por ISP) ----
        baseUrl: "${brand.baseUrl}"
        notificationsUrl: "${brand.notificationsUrl || ''}"
        notificationsEnabled: ${brand.notificationsEnabled ? 'true' : 'false'}
        isCatchupClient: ${brand.isCatchupClient ? 'true' : 'false'}

        ' Plataforma del backend: 12 = Roku. Fijo, no cambia por ISP.
        ' (verificado en app-lg/src/js/login.js:13 — enum OS)
        platform: 12

        ' ---- Pestañas (switch maestro; se combina con lo que mande el backend) ----
        tabHomeEnabled: ${tabs.home ? 'true' : 'false'}
        tabEventsEnabled: ${tabs.events ? 'true' : 'false'}
        tabContentEnabled: ${tabs.content ? 'true' : 'false'}

        ' ---- Imágenes de marca (se copian desde brands/<isp>/images/) ----
        logoUri: "pkg:/images/brand_logo.png"
        introUri: "pkg:/images/brand_intro.png"
        loginUri: "pkg:/images/brand_login.png"

        ' ---- Color de marca (único que cambia por ISP) ----
        ' Los colores de SceneGraph son 0xRRGGBBAA; brand.json los trae como #RRGGBB.
        accent: "0x" + hexOf(accent) + "FF"
        accentSoft: "0x" + hexOf(accent) + "33"   ' mismo color al 20% de opacidad

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
        ' controlSurface es el fondo de TODO control en reposo: iconos de la navbar, botones de
        ' "Mi lista"/pantalla completa y pildoras de categoria inactivas. Va calculado aqui y no en
        ' el componente: si falta, Roku recibe invalid y pinta el rectangulo BLANCO, con lo que el
        ' texto claro encima desaparece (visto en el simulador el 2026-09-21).
        glassControls: true
        glassAlpha: 0.45
        controlSurface: "0x161619" + "72"           ' surface al 45%
        controlSurfaceDisabled: "0x161619" + "4C"   ' surface al 30%

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

// ---- imágenes ----------------------------------------------------------------
const imagesSrc = path.join(brandDir, 'images');
const imagesDst = path.join(ROOT, 'src', 'images');
fs.mkdirSync(imagesDst, { recursive: true });

const REQUIRED = [
  'icon_focus_hd.png',
  'icon_focus_sd.png',
  'splash_fhd.png',
  'splash_hd.png',
  'splash_sd.png',
  'brand_logo.png',
  'brand_intro.png',
  'brand_login.png',
];

let copied = 0;
const missing = [];
for (const file of REQUIRED) {
  const from = path.join(imagesSrc, file);
  if (fs.existsSync(from)) {
    fs.copyFileSync(from, path.join(imagesDst, file));
    copied++;
  } else {
    missing.push(file);
  }
}

console.log(`\n  ISP: ${brand.name} (${isp})  v${brand.version}`);
console.log(`  backend: ${brand.baseUrl}`);
console.log(`  generado: src/manifest, src/source/config/BrandConfig.brs`);
console.log(`  imágenes: ${copied}/${REQUIRED.length} copiadas`);

if (missing.length) {
  console.warn(`\n  FALTAN imágenes en brands/${isp}/images/:`);
  missing.forEach((f) => console.warn(`    - ${f}`));
  console.warn(`  Tamaños requeridos en docs/MULTI_ISP.md §2. El canal no pasa certificación sin ellas.\n`);
} else {
  console.log('');
}

// ---- helpers -----------------------------------------------------------------
function validate(b) {
  const required = ['name', 'version', 'baseUrl', 'accent'];
  const missing = required.filter((k) => !b[k]);
  if (missing.length) {
    console.error(`brand.json incompleto, faltan: ${missing.join(', ')}`);
    process.exit(1);
  }
  if (!/^#[0-9a-fA-F]{6}$/.test(b.accent)) {
    console.error(`accent debe ser "#RRGGBB", recibido: ${b.accent}`);
    process.exit(1);
  }
}

function listBrands() {
  const dir = path.join(ROOT, 'brands');
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir).filter((f) => fs.statSync(path.join(dir, f)).isDirectory());
}

function write(file, content) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, content, 'utf8');
}
