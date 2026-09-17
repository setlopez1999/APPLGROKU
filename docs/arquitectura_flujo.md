# Arquitectura y Flujo — TV-Visor Roku

> Complementa `plan_migracion.md`. Mientras ese documento mapea CU por CU, este describe **cómo se
> conecta todo entre sí**: qué vive en memoria durante una sesión, qué es "una pantalla" en Roku, y en
> qué orden arrancan y paran los procesos concurrentes.
> Basado en el ciclo de vida verificado del original (`player.js:2195-2269`) y en cómo lo resolvió el
> rediseño Kotlin.

---

## 1. Una sola Scene, una pila de pantallas

El original es **una sola página** (`player.html`) con overlays. El rediseño Kotlin lo convirtió en
**browse-first**: un `MainScreen` con pestañas, y el reproductor a pantalla completa como destino.
En Roku eso se traduce así:

- **Una única `Scene`** (`MainScene`). No se crean escenas nuevas.
- Cada "pantalla" es un `Group` hijo que se **apila y se oculta**, no una escena aparte.
- `MainScene` es el dueño de: el nodo global, los Tasks de sesión, el nodo `Video`, la pila de
  pantallas y el `onKeyEvent` raíz.

```
MainScene
├─ m.global                (estado compartido, observable)
├─ VideoNode               ÚNICO en toda la app
├─ screenStack[]           pila de Groups
│   IntroScreen → LoginScreen → MainScreen ─┬─ LiveScreen      (arranca aquí)
│                                            ├─ MyListScreen
│                                            ├─ SearchScreen
│                                            └─ ProfileScreen
│   sobre cualquiera: FullscreenPlayer, EpgScreen
└─ modalLayer              AdultPin / Premium / Restriction / Offline
```

Por qué así y no con varias escenas: cambiar de escena en Roku **destruye el árbol de nodos**, y con
él el nodo `Video`. Eso reventaría el zapping y obligaría a re-crear el decodificador en cada
navegación — justo lo que `BACKEND-GOTCHAS.md` §9 dice que hay que evitar.

---

## 2. Ciclo de vida de la sesión

Orden de arranque, calcado del original (`window.onload`) y del Kotlin:

```
1. main.brs crea la Scene y el nodo global
2. Reloj de UI (1 s)                          → nodo Timer
3. ConnectivityMonitor                        → CU-18
4. ¿Hay sesión en el registry?                → sí: MainScreen · no: Intro/Login
5. Crear el nodo Video (una sola vez)
6. loadUserData()                             → Task de get-web2 (primera carga)
7. getEpgData()                               → Task de get-epgguide, EN PARALELO, no espera
8. Primer canal permitido → reproducir        → dispara heartbeat y revalidación
9. Polling de notificaciones                  → CU-19
```

Los cuatro procesos concurrentes durante una sesión activa:

| Proceso | Cada | Cómo | Se detiene cuando | CU |
|---|---|---|---|---|
| Heartbeat al dashboard | 15 s | `Timer` → `HeartbeatTask` | Modal de restricción abierto, o fin de sesión | 16 |
| Revalidación (sesión + canales + EPG) | 60 s | `Timer` → `RevalidateTask` | Fin de sesión | 17 |
| Polling de notificaciones | 60 s | `Timer` → `NotificationsTask` | Fin de sesión | 19 |
| Conectividad | reactivo | `ConnectivityMonitor` | Fin de sesión | 18 |

**Diferencia importante con el Kotlin**: allí los tres primeros son corrutinas en `viewModelScope` y
se cancelan solas al destruir el ViewModel. En Roku **no hay cancelación automática**: cada `Timer`
se para y cada `Task` se marca `control = "stop"` explícitamente en el logout y al salir del canal.
Si se olvida, quedan corriendo y hacen peticiones con un token muerto — es el equivalente exacto del
bug de intervals apilados del original (CU-19).

**Ritmo adaptativo** (`BACKEND-GOTCHAS.md` §6 y §7): si el estado está degradado (sin canal
reproducible, o la guía llegó vacía), reintentar **más seguido**, y relajar el ritmo al recuperarse.
La guía se reintenta **por su cuenta** aunque la lista de canales no haya cambiado.

---

## 3. El estado global reemplaza a las variables globales

El original tiene ~25 variables globales (`../app-lg/docs/cu/STATE.md`). En Roku van al nodo
`m.global`, que cualquier componente puede observar con `observeField`:

| Categoría en el original | Dónde vive en Roku |
|---|---|
| `userInfo`, `mac` | `m.global.session` (+ registry para lo persistente) |
| `allChannels`, `allSections`, `favorites` | `m.global.channels` / `.sections` / `.favoriteIds` |
| `channelActive`, `urlActual` | `MainScene` (estado de reproducción, no de dominio) |
| `sideChannelOpen`, `epgActivated`, `optionsOpen`, `favOpen` | Un solo campo `activeScreen` (la pila de §1) |
| `premiumModalShowing`, `adultoModalShowing`, … | Un solo campo `activeModal` |
| `multiCdnEnabled`, `multiCdnUrl`, `deviceIp` | Privados del `MultiCdnRepository`, nunca en `m.global` |
| `activityTimer`, `longPoolingInterval*`, `timeLineInterval` | Nodos `Timer` con dueño explícito |

**Regla**: si dos componentes necesitan el mismo dato, lo observan del nodo global. Nunca se lo pasan
entre ellos ni lo duplican.

---

## 4. Botón Back — una sola fuente de verdad

Todo el Back se resuelve en `MainScene.onKeyEvent`, en este orden (ver `plan_migracion.md` §6):

```
modal abierto        → cerrar modal
pantalla completa    → volver a LiveScreen
EPG abierto          → cerrar EPG
pantalla apilada     → volver a la pestaña
pestaña != inicial   → volver a "TV en directo"
raíz                 → devolver false y dejar que Roku cierre el canal
```

En Roku no existe "salir de la app" explícito: **devolver `false`** en la raíz hace que el sistema
cierre el canal. No hay que pedir confirmación (el original lo hacía en Samsung/Android porque ahí sí
había que llamar a la plataforma).

---

## 5. El foco es manual — y es el mayor riesgo del proyecto

SceneGraph **no tiene navegación espacial**. No existe el equivalente de `SpatialNavigation.js` del
original ni del sistema de foco de Compose: el foco se mueve llamando a `setFocus(true)` sobre el
nodo que toca, y cada componente decide a quién se lo cede en cada dirección.

Esto ya mordió en los otros dos ports, por el mismo motivo:

- En **tvOS** el foco no subía de la primera fila al header y el botón de cerrar sesión quedaba
  inalcanzable (`../app-tvos/doc/error_xcode_fase_3_foco_home_no_sube_header.md`).
- En **Compose** el `BasicTextField` atrapaba el D-pad y el botón de login era inalcanzable
  (CU-01 del Kotlin), y más tarde unos botones placeholder robaban las flechas del zapping (CU-11).

**Reglas que se adoptan desde el principio**, para no repetirlo:

1. Cada pantalla declara explícitamente **su nodo con foco inicial** y qué pasa en cada borde
   (arriba/abajo/izquierda/derecha).
2. **Ningún nodo decorativo es enfocable.** Si no responde a OK, no recibe foco.
3. Al abrir un modal se **guarda** el nodo que tenía el foco y se **restaura** al cerrarlo.
4. Todo cambio de foco se prueba recorriendo la pantalla entera con el D-pad antes de dar el CU por
   cerrado. Si algo falla dos veces, se lee el código en lugar de seguir probando (`PLAN.md` §9.2).

---

## 6. Flujo de datos, ejemplo concreto: cambiar de canal

```
Usuario pulsa ↓ en pantalla completa
  → FullscreenPlayer.onKeyEvent: pasan los guards (sin modal, sin EPG)
  → sube el evento a MainScene por un campo observable
  → ZappingUseCase(canales, canalActual, haciaAbajo)  ← función pura, con test
  → devuelve el siguiente canal permitido (premium/adulto saltados), o "ninguno"
  → MainScene valida: premium → adulto → restricción IP
  → VideoNode.control = "stop" ; nuevo content ; control = "play"
  → se publica el canal activo en m.global
  → CurrentChannelDisplay, la estrella de favorito y el footer se redibujan solos (observeField)
  → al empezar a reproducir, se reinicia el Timer del heartbeat con el nuevo cn_id
```

Ningún paso llama directamente a otro fuera de esta cadena. Siempre
`componente → estado → use case → repositorio`, y el estado vuelve por `observeField`.

---

## 7. Qué NO se puede replicar del Kotlin (y qué se hace en su lugar)

| En Kotlin | En Roku | Consecuencia |
|---|---|---|
| Corrutinas cancelables (`viewModelScope`) | `Task` + `Timer` parados a mano | Hay que parar todo explícitamente en logout y salida |
| Hilt / inyección de dependencias | Módulos BrighterScript + paso por parámetro | Los use cases reciben lo que necesitan; nada de singletons ocultos |
| `StateFlow` | `observeField` sobre `m.global` | Equivalente práctico; sin operadores (`combine`, `map`) — se compone a mano |
| Foco automático de Compose | `setFocus` manual | Ver §5 |
| Product flavors | `brands/<isp>/` + script de build | Ver `MULTI_ISP.md` |
| bcrypt (`at.favre.lib`) | **No existe** | CU-14 bloqueado, ver `plan_migracion.md` §8.1 |
| Botones CH+/CH- | El control de Roku no los tiene | Zapping solo con flechas |
