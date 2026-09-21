# Plan de Port — TV-Visor (Web/JS + Kotlin) → Canal Roku

> Origen funcional: `C:\Users\PC1\Desktop\P\app-lg\` — app original JS (LG/Samsung/Android TV).
> Origen de diseño: `C:\Users\PC1\Desktop\P\app-lg-kotlin-rediseno\` (rama `NORETURNOVERLAYNEWFLOW`).
> Destino: `C:\Users\PC1\Desktop\P\applg-roku\` — canal nativo Roku (BrightScript/SceneGraph).
> Estado: **19 de 20 CU implementados**, la mayoría verificados en ejecución contra el backend
> de producción. Bitácora detallada en `PLAN.md` §10.

---

## 1. Alcance

- **Se porta**: los 20 casos de uso + el catch-up, con el diseño del rediseño Kotlin.
- **No se toca**: el backend. Los endpoints se consumen tal cual (`../app-lg/docs/API.md`).
- **Se preserva**: el modelo white-label multi-ISP.
- **Radio**: los canales con `audio: 1` son un subtipo de canal, no una app aparte — mismo
  reproductor, distinto póster.
- **Novedad respecto al original JS**: el catch-up, que en el original no existe y en el Kotlin sí.

---

## 2. Decisiones de arquitectura

| Decisión | Valor | Razón |
|---|---|---|
| Lenguaje | **BrightScript plano** (`.brs`), validado con `bsc` | *Revisado 2026-09-17*: BrighterScript daba clases y namespaces, pero el intérprete `brs` de Node (el que permite testear sin dispositivo) no lo entiende. El bucle de test vale más. Ver `../AGENTS.md` |
| UI | **SceneGraph** | Única opción real en Roku. `roScreen`/2D queda descartado: no es el camino soportado para canales modernos |
| Patrón | Estado observable + componentes tontos | Equivalente práctico del MVVM/UDF del Kotlin: los repos publican en `m.global`, los componentes hacen `observeField` |
| Red | **Task nodes** (`roUrlTransfer` asíncrono) | Obligatorio: la red en el hilo de render congela la UI |
| Persistencia | **`roRegistrySection`** | Reemplaza `localStorage`. **Límite duro de 32 KB por canal** — ver §8.4 |
| Cifrado del password | **`roEVPCipher`** (AES) | El backend pide el password en claro en cada `get-web2`; se guarda cifrado toda la sesión |
| Reproductor | Nodo **`Video`** único, HLS nativo | Un solo decodificador (`BACKEND-GOTCHAS.md` §9) |
| Tests | **`brs` en Node** (`npm test`) sobre `domain`/`data` | La lógica se prueba en el PC, en segundos, sin Roku. Rooibos queda para tests en dispositivo si hacen falta |
| Build / deploy | **`roku-deploy`** + script propio por ISP | No hay product flavors en Roku |
| Fechas | Utilidades propias sobre `roDateTime` | El original usa Moment.js; los timestamps del backend son **Unix en segundos** |

---

## 3. Mapeo CU → Roku

| CU | Descripción | Dónde vive en Roku | Notas de port |
|---|---|---|---|
| CU-01 | Login | `LoginScreen` + `AuthTask` + `LoginUseCase` | `platform=12`. `devid` aleatorio de 10 dígitos persistido en registry. Password cifrado con `roEVPCipher` |
| CU-02 | Perfil / plan | `ProfileScreen` | Sin API dedicada: lee `UserInfo` del estado global |
| CU-03 | Cambio de contraseña | `ProfileScreen` (vista informativa) | Solo texto + contacto de soporte. No hay formulario |
| CU-04 | Logout | `LogoutUseCase` + `AuthTask` | `POST api/desvincular?token=` (query param, sin body). Si falla, se cierra igual. Preservar `deviceId` y credenciales si "recordarme" |
| CU-05 | Primer canal permitido | `GetFirstAllowedChannelUseCase` | No premium, no adulto, fallback a `[0]`. **Y filtrar canales sin url resuelta** (`BACKEND-GOTCHAS.md` §5) |
| CU-06 | Lista de canales | `ChannelGrid` / `ChannelList` | En el rediseño es grid por categoría, no sidebar. Ver `DISENO.md` |
| CU-07 | Categorías | `CategoryTabs` | Píldoras horizontales. Ocultar categorías que quedan vacías tras filtrar urls |
| CU-08 | Toggle favorito | `ToggleFavoriteUseCase` + `FavoritesTask` | 3 endpoints, los 3 POST con query-string. `delete-favorite` es POST |
| CU-09 | Mi lista | `MyListScreen` | Cruce favoritos × canales vigentes; los que ya no existen se saltan |
| CU-10 | EPG | `ChannelGrid` + `EpgGrid` | Columnas FIJAS (3 pasadas + ahora + 1 futura), no anchos proporcionales. Resuelto, ver §8.3 |
| CU-11 | Zapping | `ZappingUseCase` | **Loop, no recursión.** Y **sin CH+/CH-**: el control de Roku no los tiene (§8.2) |
| CU-12 | Multi-CDN | `MultiCdnRepository` | GET `url_ip` → `deviceIp`; POST `api/get-ipurl {deviceid:1, networkid}` → `link`; `url = link + short_link`. Sin failover |
| CU-13 | Info de canal + restricción IP | `CurrentChannelDisplay` + `ValidateIpRestrictionUseCase` | `POST api/channel-allowed-ip {ip, cn_id}`; 403 → modal |
| CU-14 | Control parental | `PinModal` + `ParentalPin` | **PIN local del aparato**: el hash del backend es bcrypt y Roku no puede verificarlo. Resuelto, ver §8.1 |
| CU-15 | Premium | `PremiumModal` + `PremiumAllowedUseCase` | Se revalida cada 60 s: si el usuario compra, se cierra el modal y reproduce |
| CU-16 | Heartbeat | `HeartbeatTask` + nodo `Timer` (15 s) | `GET {token}/{cn_id}.json`, fire-and-forget. Se reinicia al empezar a reproducir |
| CU-17 | Revalidación | `RevalidateTask` + nodo `Timer` (60 s) | Si `error==true` → logout. Reconstruir **solo si algo cambió** (`BACKEND-GOTCHAS.md` §6) |
| CU-18 | Offline | `ConnectivityMonitor` | `roDeviceInfo.GetLinkStatus()` + fallo de las peticiones. No replicar el `setTimeout` incondicional del original |
| CU-19 | Notificaciones | `NotificationsTask` + `NotificationToast` | Polling 60 s. Un solo Task, sin apilar timers |
| CU-20 | Marcar leídas | `MarkNotificationsReadUseCase` | Una petición por notificación, sin batch |
| — | **Catch-up** | `CatchupUseCase` + `CatchupAvailabilityRepository` | URL construida: `{live sin .m3u8}_dvr_range-{inicioSeg}-{duraciónSeg}.m3u8`. **Sondear** antes de ofrecerlo y cachear (§8.5) |

---

## 4. Modelos de dominio

Basados 1:1 en `../app-lg/docs/cu/MODELS.md`. Parseo **tolerante**: claves desconocidas se ignoran,
todo campo ausente tiene valor por defecto (`BACKEND-GOTCHAS.md` §6).

`Channel` (+ `sectionPremium`, `sectionAdulto`, `sectionId`, `sectionNombre` copiados del padre;
`restriccion`; `catchup`; `adulto` propio del canal, que a veces solo viene ahí) · `UserInfo` ·
`Plan` · `Section` (con `categoryIndex`) · `Category` · `EpgProgram` (timestamps **en segundos**) ·
`Notification` · `BrandConfig`.

Dos avisos heredados del Kotlin:

- El flag **adulto real puede venir en el canal** (`adulto`), no solo en la sección. Al aplanar,
  marcar adulto si **canal o sección** lo indican.
- `cn_id` llega como **número**; `user_id` llega como número en unos ISP y **texto** en otros.

---

## 5. Estructura de carpetas

Ver `../AGENTS.md`. Lo esencial: `src/source/` es BrightScript puro y testeable; `src/components/`
es la vista; la red solo en `src/components/tasks/`.

---

## 6. Prioridad del botón Back

Réplica del original (`../app-lg/docs/cu/STATE.md`), adaptada a Roku:

1. Modal abierto (adulto / premium / restricción / offline) → cerrar modal
2. Reproductor a pantalla completa → volver a `LiveScreen`
3. EPG abierto → cerrar EPG
4. Pantalla apilada (Perfil, Mi lista, Buscar) → volver a la pestaña anterior
5. Pestaña distinta de la inicial → volver a "TV en directo"
6. En la pantalla raíz → **dejar que Roku cierre el canal** (no hay "salir de la app" propio)

Un único punto de decisión en `MainScene.onKeyEvent`, no handlers dispersos.

---

## 7. Multi-ISP

Un `brands/<isp>/` + script de build que genera `manifest` y `BrandConfig`. Cada ISP es un **canal
distinto en el Roku Developer Dashboard**. Runbook en `MULTI_ISP.md`.

---

## 8. Decisiones (las que quedan abiertas están marcadas)

### 8.1 — CU-14: el PIN parental y bcrypt · **RESUELTA 2026-09-21**

El backend manda `parentlockcode` como hash **bcrypt con coste 10** (`$2y$10$...`, visto en la
cuenta real). Verificarlo exige ~2^10 expansiones de clave de Blowfish — alrededor de un millón de
cifrados de bloque — y Roku solo expone md5/sha1/sha256 y AES. Se puede escribir Blowfish a mano en
BrightScript, pero tardaría **minutos por intento**: inservible con un mando en la mano.

**Decisión: PIN local del aparato** (`domain/usecase/ParentalPin.brs` + `data/local/Session.brs`).
La primera vez que alguien abre un canal de adultos, la app le pide crear un PIN de 4 dígitos y
guarda su sha256 con el `deviceId` como sal. No sale nada al backend.

Por qué es aceptable: un control parental en una TV protege de **un niño en casa**, no de un
atacante remoto. Y con un PIN de 4 dígitos — 10.000 combinaciones — el ataque real es probarlas
todas, no romper el hash; bcrypt solo lo hace más lento, no imposible. Además, hoy el hash ya viaja
al cliente en cada `get-web2`.

Detalles que importan:
- El PIN **sobrevive al cierre de sesión**, igual que el `deviceId`. Si se borrara, cualquiera lo
  saltaría haciendo logout y volviendo a entrar.
- Una vez validado, los adultos quedan **desbloqueados durante la sesión**: pedirlo en cada canal es
  insufrible con un mando.
- **Peaje honesto**: este PIN NO coincide con el que el usuario tenga configurado en el móvil o en
  la web. Se le avisa en pantalla al crearlo.

**Mejora pendiente (no bloqueante)**: si el backend expone algún día un
`POST api/validate-parental {token, code} → {valid}`, se cambia SOLO `ParentalPin.brs` y el PIN
vuelve a ser el mismo en todas las plataformas. Ese endpoint resolvería lo mismo para cualquier
plataforma futura sin bcrypt.

### 8.2 — CU-11: zapping sin CH+/CH-

El control de Roku no tiene botones de canal. Del CU-11 original solo sobrevive el disparador de
flechas ↑↓ en pantalla completa (que es además lo que hace el rediseño Kotlin). Queda decidir si se
quiere algún equivalente extra (p. ej. `Replay` o `*`/Options) o se deja solo con flechas.
**Propuesta: solo flechas**, igual que el rediseño.

### 8.3 — CU-10: cómo se dibuja la grilla del EPG · **CERRADA 2026-09-21**

Se temía tener que dibujar celdas de ancho proporcional a la duración, que `RowList`/`MarkupGrid` no
soportan. **Al leer el rediseño Kotlin resultó que no hace eso**: `LiveViewModel.buildEpg()` usa un
número **fijo** de columnas por fila (`EPG_PAST_COUNT = 3`, `EPG_FUTURE_COUNT = 1`), y la ventana es
*maleable* — el número real se ajusta a los datos, con esos topes. Si el ISP no manda nada pasado,
no se dibuja ninguna columna pasada, así no quedan cuadros vacíos.

Eso se porta a SceneGraph sin pelearse con el layout. Implementado y testeado en
`domain/usecase/EpgGrid.brs`. Queda por medir el rendimiento en un Roku de gama baja, pero ya no hay
un problema de diseño que resolver.

### 8.4 — Registry de 32 KB

`roRegistrySection` tiene un límite total de **32 KB por canal**. El original guarda el `user_info`
completo en `localStorage`; ese JSON puede acercarse al límite. **Regla propuesta**: en registry solo
lo mínimo persistente (deviceId, email, password cifrado, rememberMe, flags); el `UserInfo` completo
vive en memoria y se recarga de `get-web2` al arrancar. Confirmar tamaño real con una cuenta grande.

### 8.5 — User-Agent del reproductor · **RESUELTA 2026-09-21**

La vía obvia (`CreateObject("roHttpAgent")` + `video.setHttpAgent()`) **no sirve**: crear el agente
en el hilo de render dispara el watchdog y mata la reproducción antes de empezar. Verificado en un
Roku Express (`ROKU-GOTCHAS.md` §23).

**La vía buena son las cabeceras del contenido:**

```brightscript
content.HttpHeaders = ["User-Agent: APPMOVIL-roku"]
```

El campo existe (el aparato no lo rechaza) y el vídeo arranca. **Queda un fleco honesto**: que el
servidor reciba de verdad esa cabecera no se ha podido comprobar, porque la cuenta de pruebas es de
Oneplay y Oneplay NO exige el User-Agent. Hay que repetirlo contra un ISP de Playcom, que es quien
devuelve 403 sin él.

### 8.6 — Certificados TLS

En BrightScript, `roUrlTransfer` sobre HTTPS necesita `SetCertificatesFile("common:/certs/ca-bundle.crt")`
y `InitClientCertificates()`. Sin eso, **todas** las llamadas fallan sin mensaje claro. Se encapsula
en un único helper de `util/` que construya todos los `roUrlTransfer`; nadie crea uno a mano.

---

## 9. Bugs del original a NO replicar

Heredados ya verificados (`../app-lg-kotlin-rediseno/docs/plan_migracion.md` §8.1):

| Bug | CU | Qué pasa | Qué hacer en Roku |
|---|---|---|---|
| Zapping recursivo | CU-11 | Si todos los canales son premium/adulto, no termina | Loop con tope = nº de canales; devolver "ninguno" |
| `allSections.length < 0` | CU-05 | Guard inútil, nunca es cierto | Comprobar lista vacía de verdad |
| `setTimeout` incondicional | CU-18 | Se ejecuta aunque la reconexión haya ido bien | Solo en la rama offline |
| Intervals de notificaciones sin limpiar | CU-19 | Se apilan si se llama dos veces | Un solo Task, parado al salir |
| Variable equivocada en la revalidación | CU-17 | Usa la del bucle en vez de la encontrada | Usar la correcta explícitamente |

---

## 10. Referencias

- `BACKEND-GOTCHAS.md` (copia local, es la misma que la del repo Kotlin)
- `../app-lg/docs/` — spec funcional agnóstica (CU, MODELS, STATE, API, CONFIG)
- `../app-lg-kotlin-rediseno/` — diseño de referencia y solución de cada CU
- `../app-tvos/doc/` — errores de foco y navegación en tvOS; **aplican por analogía**: el foco manual
  de SceneGraph tiene los mismos modos de fallo que `@FocusState`
