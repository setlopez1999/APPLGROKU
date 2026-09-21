# MULTI_ISP.md — Cómo sacar un ISP nuevo (canal Roku)

> **Qué es**: el runbook para generar un canal white-label para un ISP. Es el equivalente Roku de los
> product flavors de Gradle del repo Kotlin y del `config.js` + `build-android.js` del original.
> **Principio**: **un ISP = una carpeta `brands/<isp>/`.** Todo lo personalizable vive ahí. Nada de
> buscar-reemplazar por el código.
> **Última actualización**: 2026-09-17

---

## 1. Comparación con los otros repos

| Paso en Kotlin (product flavor) | Equivalente en Roku |
|---|---|
| `buildConfigField("BASE_URL", …)` | clave en `brands/<isp>/brand.json` → `BrandConfig.brs` generado |
| `applicationId = "tv.cdlatam.<isp>"` | **no existe**: cada ISP es un **canal distinto** en el Developer Dashboard |
| `resValue("string", "app_name", …)` | `title=` del `manifest` (generado) |
| `src/<isp>/res/drawable/banner.png` | `brands/<isp>/images/` → copiado a `src/images/` |
| `signingConfig` + `keystore.properties` | clave de firma **del dispositivo de desarrollo** (`genkey`), no un archivo del repo |
| `./gradlew assemble<Isp>Release` | `npm run build:<isp>` → `roku-deploy` (sideload) o paquete firmado |

La diferencia grande: en Gradle un solo proyecto produce N APKs con distinto `applicationId`. En Roku
**no hay identidad de paquete**: la identidad es el canal publicado. Un ISP = un canal.

---

## 2. Todo lo personalizable por ISP

### `brands/<isp>/brand.json`

| Clave | Tipo | Rol |
|---|---|---|
| `name` | String | Nombre mostrado y `title` del `manifest` |
| `badge` | String | Badge corto junto al logo (país/edición). Vacío = no se dibuja |
| `version` | String | `major/minor/build` del `manifest` y versión mostrada en el perfil |
| `baseUrl` | String | URL base del backend |
| `notificationsUrl` | String | Servicio de notificaciones (**distinta** de `baseUrl`) |
| `notificationsEnabled` | Boolean | Feature flag |
| `isCatchupClient` | Boolean | El ISP es cliente de catch-up |
| `accent` | String hex | **Único** color de marca; sus variantes se derivan |
| `tabs.home` / `tabs.events` / `tabs.content` | Boolean | Switches maestros de pestañas (§4 de `DISENO.md`) |
| `splashColor` | String hex | Color del splash del canal |

`platform` **no** está aquí: es siempre **12** (Roku) y vive en el código.

### `brands/<isp>/images/`

| Imagen | Tamaño | Para qué |
|---|---|---|
| `icon_focus_hd.png` | 336×210 | Icono del canal en la parrilla de Roku (HD) |
| `icon_focus_sd.png` | 248×140 | Icono (SD) |
| `splash_fhd.png` | 1920×1080 | Splash al abrir |
| `splash_hd.png` | 1280×720 | Splash (HD) |
| `splash_sd.png` | 720×480 | Splash (SD) |
| `brand_logo.png` | según diseño | Logo interno (navbar y login) |
| `brand_intro.png` | 1920×1080 | Fondo de la pantalla de intro |
| `brand_login.png` | 1920×1080 | Fondo del login |

> Los tamaños de icono y splash son los que pide Roku. **Verificar contra la documentación oficial
> al generar el primer paquete** — si alguno no cuadra, la certificación lo rechaza.

---

## 2.b Cambiar de ISP en un comando

```bash
HOST=<ip-roku> PASS=<clave-dev> sh scripts/dev-cycle.sh <isp>
```

Genera la marca, empaqueta, instala y deja la consola volcando. **Verificado el 2026-09-21** en un
Roku Express: pasar de Oneplay a Playcom cambió nombre, color de acento y backend sin tocar código.

Un detalle observado al alternar: el **registro del aparato se comparte** entre ISPs mientras se
sideloadea en el mismo hueco de desarrollo, así que las credenciales recordadas de un ISP aparecen
en el otro. En producción no pasa — cada ISP es un canal distinto con su propio registro — pero al
probar conviene tenerlo en cuenta.

## 3. Paso a paso: añadir un ISP

1. **Copiar** `brands/<isp-existente>/` y renombrarla al ISP nuevo.
2. **Rellenar** `brand.json` con los valores de la tabla §2.
3. **Reemplazar** las imágenes de `brands/<isp>/images/` (todas, con los tamaños exactos).
4. **Generar**: `npm run build:<isp>` → escribe `manifest`, `src/source/config/BrandConfig.brs` y
   copia las imágenes a `src/images/`.
5. **Sideload** en un Roku de pruebas (`npx roku-deploy`) y verificar: login real, foco con el D-pad,
   reproducción, catch-up si aplica.
6. **Empaquetar y publicar** (§5).

---

## 4. Lo que genera el build (y por tanto NO se edita a mano)

```
manifest                              ← generado
src/source/config/BrandConfig.brs     ← generado
src/images/*                          ← copiadas de brands/<isp>/images/
```

Si alguien edita uno de estos a mano, el siguiente build lo pisa sin avisar. Los tres están en
`.gitignore` por ese motivo: la fuente de verdad es `brands/`.

---

## 5. Firma y publicación (crítico, y distinto de Android)

En Roku **no hay keystore en el repositorio**:

1. El canal se **empaqueta desde un dispositivo Roku en modo desarrollador**, con una clave generada
   en ese dispositivo (`genkey` desde la consola de desarrollo). Esa clave identifica al publicador.
2. **La clave hay que conservarla**: el mismo canal solo se puede actualizar si se firma con la misma
   clave. Si se pierde, hay que crear un canal nuevo — el equivalente al desastre del "upload key"
   que ya documentaron para Play Console.
3. Se publica en el **Roku Developer Dashboard**, como canal público (pasa certificación) o como
   canal privado/beta con código de acceso.
4. Cada ISP es un canal independiente, con su propio listado, iconos y descripción.

**Regla**: las claves y credenciales de publicación se gestionan **fuera de git**, igual que se hace
con los keystores de Android.

---

## 6. Checklist antes de entregar un ISP

- [ ] `brand.json` completo (backend, notificaciones, catch-up, acento, pestañas)
- [ ] Las 8 imágenes, con los tamaños exactos
- [ ] `npm run build:<isp>` genera `manifest` + `BrandConfig` sin avisos
- [ ] Sideload en Roku real: login con cuenta del ISP, reproducción y catch-up verificados
- [ ] Recorrido completo del foco con el D-pad, sin elementos inalcanzables
- [ ] Paquete firmado con la clave del ISP (y la clave guardada donde toca)
