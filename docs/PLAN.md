# PLAN.md — Plan Maestro de Construcción · TV-Visor Roku

> **Qué es este documento**: el mapa maestro del "cuerpo" del canal. Cómo arranca, cómo se centraliza
> la configuración y la marca, las reglas de arquitectura, el orden de construcción de los 20 casos
> de uso y cómo se verifica en un Roku real.
> **Qué NO es**: no repite el detalle interno de cada CU. Eso vive en `docs/cu/CU-XX-*.md`.
> **Última actualización**: 2026-09-17

---

## 0. Cómo leer la documentación (sin duplicar)

| Documento | Para qué |
|---|---|
| **PLAN.md** (este) | Cuerpo del canal: arranque, config, marca, reglas, orden de CUs, fases, verificación, bitácora |
| `../AGENTS.md` | Reglas duras, jerarquía de fuentes de verdad, hallazgos ya verificados |
| `BACKEND-GOTCHAS.md` | **Leer antes que nada.** Trampas del backend y del streaming verificadas en producción |
| `ROKU-GOTCHAS.md` | Trampas de la plataforma Roku. Se va llenando a medida que se verifican en dispositivo |
| `plan_migracion.md` | Alcance, decisiones de arquitectura, mapeo CU→Roku, decisiones abiertas |
| `arquitectura_flujo.md` | Cómo se conecta todo: pila de pantallas, ciclo de vida de la sesión, estado global, botón Back |
| `DISENO.md` | **Paridad visual con el rediseño Kotlin**: pantallas, tokens de marca, reglas de foco |
| `MULTI_ISP.md` | Runbook para sacar un ISP nuevo (brand.json, manifest, imágenes, publicación) |
| `cu/CU-XX-*.md` | Detalle técnico de cada CU: flujo, componentes, edge cases, tests |

Regla: si algo ya está detallado en un CU, aquí solo se referencia. PLAN.md orquesta; los CU detallan.

---

## 1. Objetivos que condicionan todo el diseño

1. **Paridad visual con el rediseño Kotlin.** El diseño no se reinventa: se replica. Cuando SceneGraph
   no permita algo exacto, se documenta la desviación en `DISENO.md` antes de implementarla.
2. **Paridad funcional con el original.** Los 20 CU, sin comportamiento inventado.
3. **Hardware Roku de gama baja.** Los ISP ponen dispositivos baratos (Express, Streaming Stick de
   generaciones viejas). Eso obliga a: listas perezosas (`RowList`/`MarkupGrid` con `numRows`
   acotado), imágenes del tamaño exacto en que se dibujan, y **cero trabajo pesado en el hilo de
   render**.
4. **Multi-ISP (white-label).** Un canal por ISP, generado desde `brands/<isp>/`. Ver `MULTI_ISP.md`.
5. **Degradar con elegancia.** El backend cambia campos en caliente (`BACKEND-GOTCHAS.md` §6): que
   falte un campo no puede romper el parseo ni la reproducción.

**Resolución objetivo**: `ui_resolutions=fhd`, diseño a **1920×1080** y Roku escala a 720p solo. Todas
las medidas de `DISENO.md` están en píxeles de 1920×1080.

---

## 2. Arranque del canal (el "esqueleto")

```
main.brs
  └─ CreateObject("roSGScreen") + roMessagePort
     └─ screen.CreateScene("MainScene")
        ├─ m.global  ← nodo de estado compartido (sesión, canales, favoritos, EPG, conectividad)
        ├─ Tasks de sesión (red + temporizadores)
        └─ pila de pantallas (una Group por pantalla, apilada sobre MainScene)
            ├─ IntroScreen      (CU-01 previo)
            ├─ LoginScreen      (CU-01)
            ├─ MainScreen       → TopNavBar + pestaña activa
            │    ├─ LiveScreen      (CU-05..13, la pantalla principal)
            │    ├─ MyListScreen    (CU-09)
            │    ├─ SearchScreen
            │    └─ ProfileScreen   (CU-02, 03, 04, 19, 20)
            ├─ FullscreenPlayer (CU-05, 11, catch-up)
            └─ Modales: AdultPin / Premium / Restriction / Offline (CU-14, 15, 13, 18)
```

- **Una sola `Scene`.** Las pantallas son `Group`s que se apilan y se ocultan, no escenas distintas —
  igual que el Kotlin tiene un `NavHost` mínimo y todo lo demás es estado. Detalle en
  `arquitectura_flujo.md` §1.
- El nodo `Video` **se crea una sola vez** y lo comparten `LiveScreen` (preview) y `FullscreenPlayer`.
  Ver `BACKEND-GOTCHAS.md` §9 y `ROKU-GOTCHAS.md`.
- Los procesos concurrentes de la sesión (heartbeat 15 s, revalidación 60 s, notificaciones 60 s,
  conectividad) son **Task nodes + nodos `Timer`**, arrancados y parados por `MainScene`.

---

## 3. Configuración centralizada (marca + ISP)

Todo lo que cambia por ISP se reduce a un puñado de valores, igual que en el Kotlin:

| Valor | Rol |
|---|---|
| `baseUrl` | URL base del backend (todas las llamadas API) |
| `notificationsUrl` | URL del servicio de notificaciones (**distinta** de baseUrl) |
| `notificationsEnabled` | Feature flag on/off |
| `isCatchupClient` | El ISP es cliente de catch-up |
| `appName` / `appBadge` | Nombre mostrado y badge junto al logo |
| `accent` | **Único color de marca**; sus variantes se derivan |
| `tabHome` / `tabEvents` / `tabContent` | Switches maestros de pestañas |
| `platform` | **12** (Roku). Fijo, no cambia por ISP |

**Cómo se centraliza (una sola fuente de verdad):**

```
brands/<isp>/brand.json  +  brands/<isp>/images/
        │
        └─ scripts/build-isp.js
              ├─ genera  manifest                 (título, iconos, splash, versión)
              ├─ genera  src/source/config/BrandConfig.brs
              └─ copia   brands/<isp>/images/ → src/images/
```

- **Nadie hardcodea una URL ni un color en ningún otro lado.** Todo sale de `BrandConfig`.
- `notificationsUrl` y `baseUrl` son campos **separados**, no se deriva uno del otro.
- El `manifest` es generado, **no se edita a mano** (si se edita, el siguiente build lo pisa).
- Runbook completo en `MULTI_ISP.md`.

---

## 4. Tema y color

- **Un solo lugar**: `BrandConfig`. Fuera de ahí, ningún componente define un color suelto.
- El **único color dinámico por ISP** es `accent`; `accentSoft` se deriva bajando opacidad.
- Los **neutros son fijos** (escala oscura casi negra) y no cambian por cliente.
- El **contorno de foco es blanco, 3 px, en toda la app** — no depende del color de marca. Esto es
  deliberado en el rediseño Kotlin y se replica.
- Detalle de tokens y equivalencias en `DISENO.md`.

---

## 5. Estado y repositorios

Cada repositorio es **dueño único** de su porción de estado y la publica en el nodo global. Los
componentes observan; nunca duplican la fuente de verdad.

| Repositorio | Estado que posee | CUs |
|---|---|---|
| `AuthRepository` | sesión, login, logout, desvincular, `loadUserData` | 01, 04, 05, 17 |
| `SessionLocal` (registry) | `UserInfo`, `deviceId`, password cifrado, rememberMe | 01, 02, 03, 04 |
| `ChannelRepository` | `allChannels`, `allSections` (+ reescritura multi-CDN, + filtro de url vacía) | 05, 06, 07, 11, 12 |
| `FavoritesRepository` | ids de favoritos | 08, 09 |
| `EpgRepository` | guía EPG (con reintento propio si llega vacía) | 10, 13 |
| `MultiCdnRepository` | `deviceIp`, `multiCdnUrl` (privados) | 12 |
| `IpRestrictionRepository` | validación IP por canal | 13 |
| `CatchupAvailabilityRepository` | sonda de DVR por canal + caché | catch-up |
| `NotificationsRepository` | notificaciones, polling, marcar leídas | 19, 20 |
| `ConnectivityMonitor` | online/offline | 18 |

El estado de **reproducción** (canal activo, url actual, pantalla activa, modal abierto) vive en
`MainScene`, no en los repos: es estado de UI, no de dominio.

---

## 6. Reglas de oro (obligatorias)

### 6.1 Separación de capas
`components → domain → data`. `domain` no importa nodos ni hace red. (→ `AGENTS.md`)

### 6.2 Red solo en Task nodes
Ni una llamada HTTP fuera de `components/tasks/`. Un `roUrlTransfer` síncrono en el hilo de render
congela la UI y Roku lo castiga con watchdog.

### 6.3 Un solo nodo Video
Se crea una vez y se reutiliza. Para pasar de vivo a grabación: `control = "stop"` y luego nuevo
`content`. **Pausar no libera el decodificador** (`BACKEND-GOTCHAS.md` §9).

### 6.4 Coherencia de patrón
Ver `AGENTS.md`. Mismo molde en los 20 CU; los cambios de convención se aplican retroactivamente.

### 6.5 Diseño desacoplado
La lógica (`domain`/`data`) no conoce colores, medidas ni nombres de nodos. Cambiar el diseño toca
`components/` y `BrandConfig`, nunca `domain/`.

---

## 7. Los 20 Casos de Uso — orden de construcción

**Fase 0 — Esqueleto y herramientas**
Estructura, `manifest`, toolchain (`bsc` + `brs` + `roku-deploy`), `BrandConfig` de un ISP, pantalla
mínima que arranca en el dispositivo. **Portar el test de auditoría de streams** (ver §9.2).

**Fase 1 — Auth + base** (HTTP, parseo tolerante, registry)
- CU-01 Login · CU-04 Logout · CU-02 Perfil/plan · CU-03 Cambio de contraseña (informativo)

**Fase 2 — Reproducción**
- CU-05 Primer canal permitido · CU-12 Multi-CDN · CU-11 Zapping (solo flechas, ver `AGENTS.md`)

**Fase 3 — Navegación de canales**
- CU-06 Lista de canales · CU-07 Categorías · CU-08 Toggle favorito · CU-09 Mi lista · CU-13 Info de
  canal + restricción IP

**Fase 4 — EPG**
- CU-10 Guía · y sobre ella, el **catch-up** (celdas pasadas reproducibles, con sonda de DVR)

**Fase 5 — Seguridad**
- CU-14 Control parental (**bloqueado hasta resolver bcrypt**, ver `plan_migracion.md` §8) · CU-15 Premium

**Fase 6 — Conectividad y métricas**
- CU-16 Heartbeat 15 s · CU-17 Revalidación 60 s · CU-18 Offline

**Fase 7 — Notificaciones**
- CU-19 Polling · CU-20 Marcar leídas

**Fase 8** — Multi-ISP y empaquetado por cliente · **Fase 9** — QA de rendimiento en Roku de gama baja.

> El orden respeta el del Kotlin salvo una cosa: **el catch-up sube a la Fase 4**, pegado al EPG,
> porque en el Kotlin se hizo después y obligó a rehacer la grilla.

---

## 8. Herramientas

| Área | Herramienta | Estado | Nota |
|---|---|---|---|
| Lenguaje | BrightScript plano (`.brs`) | ✅ | Ver la decisión revisada en `AGENTS.md` |
| Validación | **brighterscript** (`bsc`) — `npm run lint` | ✅ instalado, 0 diagnósticos | Compila y valida todo el proyecto sin dispositivo |
| Tests | **@rokucommunity/brs** — `npm test` | ✅ instalado, **100 tests en verde** | Ejecuta BrightScript en Node. Sin Roku |
| Deploy | **roku-deploy** | ✅ instalado, sin probar | Empaqueta `src/` y hace sideload por HTTP |
| Logs | telnet al puerto **8085** del Roku | pendiente de dispositivo | Consola de depuración |
| Teclas | **ECP** (puerto 8060) | pendiente de dispositivo | `curl -d '' http://<ip>:8060/keypress/Down` |
| Tests en dispositivo | Rooibos | no instalado | Opción futura; corre dentro del canal, no sustituye a `npm test` |

---

## 9. Verificación en Roku real

### 9.0 Qué se puede probar sin Roku, y qué no

**Roku no publica un emulador oficial**, pero existe **`brs-desktop`** (simulador de la comunidad,
basado en `brs-engine`) y **cambia bastante el panorama**: trae instalador web, ECP, consola de
depuración y una implementación PARCIAL de SceneGraph. Con él ya se verificó en el PC el arranque,
el registro, el teclado, el foco y **una llamada HTTPS real al backend de producción**
(ver `ROKU-GOTCHAS.md` §18).

Lo que el simulador **no** sustituye: el render fino, el rendimiento y sobre todo el **vídeo**. Para
eso sigue haciendo falta un aparato físico — y uno de gama baja es mejor banco de pruebas, porque es
lo que tienen los clientes de los ISP.

Ciclo de trabajo con el simulador:

```bash
sh scripts/dev-cycle.sh                       # empaqueta + instala + lanza + vuelca la consola
node scripts/dev-keys.js Down Down OK         # teclas por ECP
node scripts/dev-keys.js --text "a@b.tv"      # escribir en un teclado en pantalla
node scripts/dev-run.js 10 127.0.0.1 --no-launch   # solo escuchar la consola
```

Lo que se puede hacer en el PC:

| Capa | Herramienta | ¿Se ejecuta sin Roku? |
|---|---|---|
| `domain/` (reglas de negocio) | `npm test` (`brs`, intérprete en Node) | **Sí**, en segundos |
| `data/remote/ApiRoutes` (urls, escapado) | `npm test` | **Sí** |
| `data/local/Session` (registro, cifrado) | solo `npm run lint` | No: `roRegistrySection` no existe fuera del aparato |
| `util/Http`, `components/tasks/` (red) | solo `npm run lint` | No: `roUrlTransfer` tampoco |
| `components/` (pantallas, foco, vídeo) | — | No. Aquí es donde el Roku es imprescindible |

`brs` **no es un emulador**: ejecuta el lenguaje, no el aparato. No dibuja nada. Por eso la lógica
puede ir muy por delante de lo que se puede ver.

Un canal de Roku **no corre en Android TV** ni en ningún otro sitio: BrightScript y SceneGraph son
de Roku. La app de Android TV es el otro proyecto (`app-lg-kotlin-rediseno`).

### 9.1 Ciclo

1. `npm run build:<isp>` → genera `manifest` + `BrandConfig`
2. `npx roku-deploy` → sideload en el dispositivo
3. Logs: `telnet <ip-roku> 8085` (dejar abierto en otra terminal)
4. Teclas por ECP, sin tocar el control:
   `curl -d '' http://<ip>:8060/keypress/{Up,Down,Left,Right,Select,Back,Home,Play}`
5. **Recorrer el foco completo** con el D-pad y confirmar que ningún elemento queda inalcanzable.

### 9.2 Reglas de auditoría eficiente (lección de los otros ports)

1. **Auditoría de streams — ✅ ya portada** (`npm run audit`, `scripts/audit-streams.js`). Recorre la
   cadena completa (manifiesto → variante → chunklist → primer segmento, comprobando el sincronismo
   MPEG-TS) y da una tabla con la causa exacta por canal. Convierte "está en negro y no sé por qué"
   en un diagnóstico, **sin tocar el Roku**:

   ```bash
   npm run audit -- --host <host> --user <email> --pass <clave> --catchup
   npm run audit -- --url "https://host:1936/dir/canal.stream/playlist.m3u8"
   ```

   Distingue los tres fallos que un "¿responde 200?" confunde: **TLS** (certificado o SNI, la señal
   puede estar perfecta), **404** (ruta inexistente) y **200 sin segmentos** (el directorio existe
   pero no entra nada). Con `--catchup` sondea además el DVR de cada canal marcado.
2. **Si el foco falla dos veces seguidas, dejar de probar a tientas y leer el código.** En CU-01 del
   Kotlin el botón inalcanzable se resolvió leyendo la pantalla, no repitiendo el D-pad.
3. **Preferir test + `curl` antes que el dispositivo.** El Roku es para confirmar render y foco; la
   correctitud de negocio se prueba más barato con un test unitario.
4. **Verificar siempre qué canal está corriendo.** En el Kotlin hubo un diagnóstico perdido por leer
   logs de otra app del mismo paquete (`BACKEND-GOTCHAS.md` §14).

---

## 10. Bitácora de ejecución

> Se llena a medida que se implementa cada CU: qué se construyó, decisiones, desviaciones y resultado
> de la verificación en dispositivo. Vacía al inicio.

| Fecha | CU | Resumen | Verificación en Roku |
|---|---|---|---|
| 2026-09-17 | **Fase 0 — esqueleto** | Estructura de carpetas, `manifest` plantilla, documentación de arquitectura (este plan, `plan_migracion`, `arquitectura_flujo`, `DISENO`, `MULTI_ISP`, `ROKU-GOTCHAS`) y copia de `BACKEND-GOTCHAS`. Sin código de negocio. | — |
| 2026-09-21 | **CU-14 desbloqueado: PIN parental local** ✅ | Se cierra la decisión 8.1, que llevaba abierta desde el principio. El hash bcrypt del backend es inverificable en Roku (minutos por intento), así que el canal gestiona su **propio PIN**, guardado como sha256 con el `deviceId` de sal. Sobrevive al logout — si no, se saltaría saliendo y volviendo a entrar — y desbloquea los adultos por sesión. Avisa en pantalla de que no coincide con el del móvil. **Ya no queda ningún CU bloqueado.** 371 tests. | ◑ Sin disparar: la cuenta de Oneplay no tiene canales de adultos |
| 2026-09-21 | **Catch-up completo** ✅ | `CatchupProbeTask`: sondea el DVR de cada canal marcado y **solo cuenta los que graban de verdad** — un 200 no basta, la chunklist puede venir vacía (§4), así que se exige al menos un `#EXTINF`. Selección de CELDA en la parrilla (←→ dentro de la fila, marco blanco propio), y OK sobre una celda pasada con grabación abre el reproductor con la url del DVR en vez del vivo; durante una grabación el zapping queda desactivado. **La app llega sola a la misma conclusión que la auditoría por terminal**: de los 4 canales marcados en Oneplay, los 4 dan 404 y no se dibuja ningún play. | ✅ Sonda y selección de celda verificadas; **la reproducción de una grabación no se pudo probar: esta cuenta no tiene ninguna** |
| 2026-09-21 | **Modales, validaciones de acceso y conectividad** ◑ | `AppModal` reutilizable para los cuatro casos del original (premium, restricción IP, offline y, cuando se resuelva bcrypt, PIN). La selección de canal pasa por `tvResolveLaunchStep` en el orden verificado del original: premium → adulto → IP, con la IP la última porque es la única que gasta red. CU-18: sondeo de red cada 5 s con `roDeviceInfo.GetLinkStatus()` y guard anti-reapertura del modal. **Bug encontrado en pantalla**: al cambiar de canal la parrilla se enfocaba en el canal ANTERIOR — asignar `channels` dispara el refoco, así que `currentCnId` hay que ponerlo ANTES. ◑ = los modales están cableados pero **no se pudieron disparar**: esta cuenta no tiene ningún canal con `restriccion=1` ni premium bloqueado (los no incluidos llegan sin url y se filtran antes). | ◑ Verificado que no rompe nada; los modales sin disparar |
| 2026-09-21 | **Favoritos, cuenta, heartbeat y revalidación** ✅ | CU-08/09 verificados contra el backend real (4 favoritos → quitar → 3 → añadir → 4). Menú de cuenta (CU-02/03) con datos reales del plan y soporte. CU-16: heartbeat cada 15 s a `{token}/{cn_id}.json`, solo mientras el vídeo está en "playing". CU-17: revalidación cada 60 s que **solo reconstruye si la huella del catálogo cambió** — medido: 6 heartbeats y **0 reconstrucciones**, o sea que no interrumpe la reproducción ni mueve el foco. Los temporizadores se paran a mano en el logout: en Roku no hay cancelación automática. **Confirmado de paso que el vídeo reproduce**: el heartbeat solo se dispara si el nodo Video reporta "playing". | ✅ En simulador, contra producción |
| 2026-09-21 | **Login real y auditoría contra producción** ✅ | Con una cuenta real de Oneplay: **login completo en el simulador** (credenciales → 200 → catálogo → LiveScreen), el aplanado da **23 canales en 2 categorías**, que cuadra exacto con `Plan A: cantidad_canales 23`, y el "recordarme" hace el viaje de ida y vuelta por el registro cifrado. `npm run audit` sobre los 23 canales: **17 entregan vídeo MPEG-TS válido**, 5 fallan por TLS (4 de ellos por el certificado vencido de `centauro.cd-latam.com`, verificado: la misma ruta da 200 por el otro hostname) y 1 da 404. **Los 4 canales marcados con `catchup=1` dan 404 en el DVR**: cero catch-up real en esta cuenta, y sin la sonda la app dibujaría el ▶ en los cuatro. Detalle en `BACKEND-GOTCHAS.md`, sección del 2026-09-21. | ✅ En simulador, contra backend de producción |
| 2026-09-21 | **Primera ejecución real en el simulador** ✅ | `brs-desktop` (simulador de la comunidad) permite instalar, lanzar, mandar teclas por ECP y leer la consola desde el PC. Herramientas nuevas: `scripts/dev-cycle.sh`, `dev-run.js`, `dev-keys.js`. **3 bugs encontrados y corregidos, ninguno detectable por el compilador**: (1) `global` es palabra reservada y reventaba el arranque con un error que no lo sugiere; (2) ocultar el teclado NO le quita el foco — el nodo invisible se comía las teclas y el siguiente ATRÁS cerraba el canal (§17); (3) un fallo de mi propio script de teclas, no de la app (`Lit_%40` no escribe la arroba, `Lit_@` sí). **Verificado funcionando**: arranque, registro, teclado, foco, y una llamada **HTTPS real a `oneplay.iptvperu.tv` con `platform=12` → HTTP 200** (§18). | ✅ En simulador. Falta aparato real para vídeo y render |
| 2026-09-21 | **"TV en directo" + cierre de la decisión §8.3** ◑ | `EpgGrid.brs` (puro y testeado): ventana de celdas de la parrilla, réplica de `LiveViewModel.buildEpg()` del Kotlin. **Al leerlo se cerró la decisión abierta §8.3**: el rediseño NO usa celdas de ancho proporcional a la duración, usa un número fijo de columnas (3 pasadas, 1 futura) que se ajusta a los datos — eso sí se porta a SceneGraph. Todas las filas quedan del mismo ancho (las que faltan, vacías) para que la rejilla no se descuadre. El ▶ de catch-up solo sale si la grabación está **sondeada**, no si el backend dice que existe. Componentes: `CategoryTabs`, `CurrentChannelDisplay`, `ChannelRowItem`, `ChannelGrid` (MarkupList, perezoso), `LiveScreen` (modo inmersivo con los tres degradados imitados por bandas de alfa) y el nodo `Video` único, prestado por `MainScene`. **341 tests, 0 fallos.** | ◑ **Nada verificado visualmente: sigue sin haber Roku.** Pendientes en el aparato: el User-Agent APPMOVIL vía `ifHttpAgent` (§8.5), si las bandas de alfa se ven como degradado o a franjas, y el recorrido del foco entre las tres zonas |
| 2026-09-17 | **CU-16, CU-18, reglas de reproducción + auditor de streams** ✅ | `Playback` (puro y testeado): heartbeat de 15 s con sus 6 guards, modal offline con guard anti-reapertura, acción al reconectar —**sin** el mensaje incondicional que el original mostraba aunque la reconexión hubiera ido bien—, reintento de HLS con el corte para urls vacías (la pantalla negra permanente de §5), y el orden premium→adulto→IP antes de reproducir. **295 tests, 0 fallos.** Y `scripts/audit-streams.js`: port del `StreamPlaybackAuditTest` del Kotlin, corre en Node sin Roku. | ✅ Auditor verificado de punta a punta contra un HLS público real: maestro → variante → 64 segmentos → primer segmento descargado y validado como MPEG-TS |
| 2026-09-17 | **Sesión + capa de red** ◑ | `SessionRules` (puro y testeado): generación del `devid` de 10 dígitos —como TEXTO, porque 9.999.999.999 no cabe en un Integer de 32 bits—, descarte de MAC guardadas por versiones viejas, qué claves sobreviven al logout y validación del formulario de login. `data/local/Session` (registro + AES con `roEVPCipher`), `util/Http` (fábrica única de `roUrlTransfer` con los certificados, y clasificación TLS/404/200) y `components/tasks/ApiTask` (toda la red, fuera del hilo de render). **265 tests, 0 fallos.** ◑ = las tres últimas piezas solo están validadas por el compilador: `roRegistrySection` y `roUrlTransfer` no existen fuera del aparato. | **Pendiente: no hay Roku disponible todavía** |
| 2026-09-17 | **Lógica: EPG, info de canal, revalidación, favoritos, notificaciones** ✅ | `util/Time` (aritmética pura de segundos Unix; el desfase horario entra como parámetro, no se lee dentro → testeable), `data/remote/ApiRoutes` (las 12 urls del contrato + percent-encoding propio, porque `roUrlTransfer.Escape()` es solo de dispositivo y las contraseñas traen `&`, `+` y `#`), `Epg` (parseo, orden por hora, programa actual/siguiente tolerando huecos, detección del 200-con-`[]`), `ChannelInfo` (CU-13, con el relleno "Programación de {canal}" que en varios ISP es el caso normal), `CatalogRefresh` (CU-17: firma del catálogo para reconstruir solo si cambió algo real, decisión sobre el canal activo, ritmo adaptativo), `Favorites` (CU-08/09), `Notifications` (CU-19/20, separando "no leída" de "nueva"). **237 tests, 0 fallos.** Dos tropiezos de lenguaje anotados en `ROKU-GOTCHAS.md` §14. | — |
| 2026-09-17 | **Fase 0 — toolchain + núcleo de lógica** ✅ | `bsc` (lint) + `brs` (tests en Node) + `roku-deploy` instalados y funcionando. Generador por ISP (`brand.json` → `manifest` + `BrandConfig.brs` + imágenes) probado con Oneplay. Implementado y testeado: parseo tolerante (`util/Json`), modelos (`Models`), aplanado del catálogo con las 3 reglas del plan del cliente (`FlattenCatalog`), premium y primer canal (`ChannelAccess`), zapping en bucle (`Zapping`), url y disponibilidad de catch-up (`Catchup`). **100 tests, 0 fallos**, sin dispositivo. **Decisión revisada**: BrightScript plano en vez de BrighterScript, para poder ejecutar los tests en Node (ver `AGENTS.md`). | — (falta Roku en la red) |
