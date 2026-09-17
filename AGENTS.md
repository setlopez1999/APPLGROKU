# TV-Visor Roku — Guía para Agentes

> **Propósito**: cualquier agente (o desarrollador) que toque este repositorio lee este archivo primero.
> **Última actualización**: 2026-09-17

## Qué es este proyecto

Canal de **Roku** (BrightScript + SceneGraph) de TV-Visor: IPTV multi-ISP con canales en vivo, EPG,
catch-up, favoritos, control parental y multi-CDN.

Dos metas, y no son la misma:

1. **Diseño**: réplica visual y de flujo del rediseño Kotlin (`app-lg-kotlin-rediseno`, rama
   `NORETURNOVERLAYNEWFLOW`). Mismo look, mismas pantallas, mismo recorrido del usuario.
2. **Funcionalidad**: paridad con el original (`app-lg`, JS). Los 20 casos de uso, sin inventar
   comportamiento nuevo.

**El "cómo" interno será distinto** y está bien que lo sea: Roku no tiene Compose, ni corrutinas, ni
inyección de dependencias, ni navegación espacial automática. Lo que se conserva es la **forma de las
capas** y el **contrato con el backend**, no las clases del Kotlin.

## Estado actual

**No hay código de negocio todavía.** Solo el esqueleto de carpetas, el `manifest` y esta
documentación. Si vas a empezar a codear, tu primer paso es la sección "Metodología" de más abajo —
no asumas que algo está hecho sin verificarlo en `src/`.

## Jerarquía de fuentes de verdad (importante, en este orden)

| Orden | Fuente | Qué aporta | Cómo tratarla |
|---|---|---|---|
| 1 | `docs/BACKEND-GOTCHAS.md` | Trampas del backend y del streaming verificadas en producción | **Dato duro.** Si algo lo contradice, gana esto |
| 2 | `../app-lg/docs/cu/CU-01..20`, `MODELS.md`, `STATE.md`, `API.md` | Spec funcional **agnóstica del lenguaje** | La spec. Es lo que la app debe hacer |
| 3 | `../app-lg-kotlin-rediseno/` (código + `docs/`) | **El diseño** (fuente de verdad visual) y cómo se resolvió cada CU | Referencia de producto y de solución |
| 4 | `../app-lg/src/js/player.js`, `login.js`, `notifications.js` | El código original | Último recurso. **Verificar antes de citar** una línea |

**Regla sobre los CU del Kotlin**: `app-lg-kotlin-rediseno/docs/cu/CU-XX.md` traen "Clases Kotlin" y
"Dependencias Gradle". Eso es **referencia de cómo se resolvió**, no spec. La spec agnóstica son los
CU de `app-lg`.

## Decisiones de arquitectura ya tomadas (no volver a discutir sin razón nueva)

- **Lenguaje: BrightScript plano (`.brs`)**, validado con el compilador de BrighterScript (`bsc`).
  *Revisado el 2026-09-17*: se iba a usar BrighterScript (`.bs`) por sus clases y namespaces, pero el
  intérprete `brs` de Node — que es lo que permite **ejecutar los tests sin dispositivo** — entiende
  BrightScript, no BrighterScript. El bucle de test en rojo/verde vale más que el azúcar sintáctico.
  `bsc` se sigue usando como validador (`npm run lint`) y empaquetador.
  Convención en su lugar: **prefijo `tv` en las funciones globales** (`tvFlattenCatalog`,
  `tvPremiumAllowed`), porque BrightScript tiene un único espacio de nombres global.
- **UI: SceneGraph** (nodos XML + BrightScript). No hay alternativa en Roku.
- **Capas**: `domain` y `data` son **BrightScript puro, sin nodos SceneGraph** → se testean sin
  dispositivo. La regla `ui → domain → data` del Kotlin se mantiene tal cual.
- **Toda la red va en Task nodes.** Nunca `roUrlTransfer` en el hilo de render — congela la UI.
- **Estado de sesión en un nodo global** (`m.global`) observado con `observeField`, que hace el papel
  del `StateFlow` del Kotlin. Una sola fuente de verdad.
- **Un solo nodo `Video` en toda la app**, reutilizado. Ver `docs/BACKEND-GOTCHAS.md` §9.
- **Persistencia: `roRegistrySection`** (reemplaza `localStorage`). Ojo con el límite de 32 KB.
- **Tests: `brs` (intérprete de BrightScript en Node), `npm test`.** Corren en el PC, sin Roku, en
  segundos. Un CU no está terminado hasta que su test pasa. Si un test necesitara un nodo SceneGraph,
  la pieza está en la capa equivocada. Deploy: `roku-deploy`.
  (Rooibos queda como opción para tests *en dispositivo* más adelante; corre dentro del canal, no en
  el PC, así que no sustituye a esto.)
- **Multi-ISP: un `brands/<isp>/brand.json` + script de build** que genera `manifest` y `BrandConfig`.
  Roku no tiene product flavors; esto es el equivalente. Ver `docs/MULTI_ISP.md`.

## Hallazgos heredados ya verificados (no re-investigar)

Del backend y del original — vienen verificados de los otros repos:

- `api/delete-favorite` es **POST**, no DELETE
- `api/desvincular` no lleva body: `POST api/desvincular?token={token}` como query param
- `api/channel-allowed-ip` el body real es `{ip, cn_id}`
- El `devid` **nunca fue una MAC**: número aleatorio de 10 dígitos persistido
- El backend **exige el password en texto plano en cada `get-web2`**, no solo en el login → hay que
  guardarlo cifrado toda la sesión, independientemente de "recordarme" (son dos cosas distintas, con
  ciclos de vida distintos)
- `user_id` llega como número en unos ISP y como texto en otros — tolerar ambos
- Heartbeat cada **15 s**, revalidación de sesión cada **60 s**
- Bugs del original **a no replicar**: recursión del zapping (CU-11), guard `allSections.length < 0`
  (CU-05), `setTimeout` incondicional al reconectar (CU-18), intervals de notificaciones sin limpiar
  (CU-19)

Específicos de Roku, confirmados al analizar el original:

- **`ROKU: 12` ya existe en el enum `OS`** (`app-lg/src/js/login.js:13` y `player.js:12`). El
  `platform` que manda este canal es **12**. No hay que pedírselo al backend.
- **El control de Roku no tiene CH+/CH-.** El CU-11 del original tiene dos disparadores (flechas y
  botones físicos) con guards distintos; en Roku **solo existe el de flechas**. No inventar un
  sustituto sin decidirlo con el usuario.
- **No hay bcrypt en Roku.** `roEVPDigest` da md5/sha1/sha256 y nada más. CU-14 (PIN parental)
  **no se puede portar tal cual** — es la decisión abierta nº1 (ver `docs/plan_migracion.md` §8).

## Metodología de implementación

**Un caso de uso a la vez, y cada uno se da por terminado solo cuando su test pasa** (`npm test`). No
avanzar al siguiente con el anterior a medias. El ciclo por CU:

1. Leer el CU de `../app-lg/docs/cu/CU-XX-*.md` **completo** (la spec) y luego su homónimo del Kotlin
   (cómo se resolvió). En ese orden.
2. Implementar primero `domain/` y `data/` — es donde vive la lógica y es lo único testeable sin
   dispositivo.
3. Escribir el test **con los edge cases ya listados en el CU**. Si el CU dice "test crítico: todos
   los canales premium/adulto → no debe crashear", ese test es obligatorio, no opcional.
4. Solo después, construir el componente SceneGraph que lo consume.
5. Verificar en Roku real: recorrido completo del foco con el D-pad, sin elementos inalcanzables
   (ver `docs/PLAN.md` §9).
6. Si aparece un caso no contemplado, **actualizar el `.md` del CU**, no solo el código.

Esto existe para evitar dos problemas concretos que ya pasaron en los otros ports: descubrir bugs de
lógica cuando ya hay UI construida encima (cuando es más caro corregir), e implementar "a ojo" sin
verificar los edge cases ya identificados.

## Estructura del proyecto

```
applg-roku/
├── src/
│   ├── manifest                 (generado por ISP desde brands/<isp>/)
│   ├── source/                  BrightScript puro — sin nodos, testeable
│   │   ├── main.brs             entrada del canal
│   │   ├── config/              BrandConfig (generado por ISP)
│   │   ├── domain/model/        Channel, Section, UserInfo, EpgProgram, Plan, Notification
│   │   ├── domain/usecase/      uno por CU o grupo
│   │   ├── data/remote/         construcción de requests (no ejecutan red)
│   │   ├── data/repository/     estado + orquestación
│   │   ├── data/local/          registry (sesión, deviceId, password cifrado)
│   │   └── util/                fechas, http, log
│   ├── components/              SceneGraph — la vista
│   │   ├── tasks/               TODA la red vive aquí
│   │   ├── screens/             Intro, Login, Main, Live, Fullscreen, MyList, Search, Profile
│   │   ├── common/              TopNavBar, CategoryTabs, ChannelCard, ChannelGrid…
│   │   └── modals/              AdultPin, Premium, Restriction, Offline
│   ├── images/                  assets de marca (se sustituyen por ISP)
│   └── locale/
├── tests/                       Rooibos
├── brands/<isp>/                brand.json + imágenes del cliente
├── scripts/                     build por ISP, deploy
└── docs/
```

**Regla de dependencias, sin excepciones**: `components → domain → data`. `domain` **nunca** importa
un nodo SceneGraph ni toca la red. Si un use case necesita algo del dispositivo, se le pasa por
parámetro.

## Coherencia de patrón

Mismo molde en los 20 CU, igual que se exigió en el Kotlin:

- **Use case**: una función pública, nombre en imperativo, un solo punto de entrada. Recibe datos,
  devuelve datos. Sin red, sin nodos, sin estado en `m.`.
- **Repository**: dueño único de su porción de estado; publica cambios escribiendo en el nodo global.
  Nunca dos repos dueños del mismo dato.
- **Screen (componente)**: un campo observable de entrada para el estado y campos de salida para los
  eventos. Ningún screen llama directo a otro screen.
- Antes de escribir un componente nuevo, mirar el anterior y replicar la forma. Un cambio de
  convención se aplica **retroactivamente** a todos, no solo hacia adelante.

## Observaciones

> Se van acumulando aquí a medida que se verifica algo contra el dispositivo real o se descubre un
> caso no contemplado. Vacía al inicio.
