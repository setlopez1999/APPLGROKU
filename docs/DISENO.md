# DISENO.md — Paridad visual con el rediseño Kotlin

> **Qué es**: la especificación de diseño del canal Roku. El objetivo del proyecto es que se vea
> **igual** que `app-lg-kotlin-rediseno` (rama `NORETURNOVERLAYNEWFLOW`); aquí quedan fijados los
> tokens, las pantallas y las reglas de foco, con las medidas ya convertidas a píxeles de Roku.
> **Fuente**: `app-lg-kotlin-rediseno/app/src/main/java/com/androidtv/ui/` (leído, no supuesto) y
> `app-lg-kotlin-rediseno/docs/REDISENO.md`.
> **Regla**: si SceneGraph no permite reproducir algo exacto, se documenta la desviación **aquí,
> antes** de implementarla. No se improvisa en el código.

---

## 0. Conversión de medidas (importante)

El Kotlin trabaja en `dp` sobre Android TV a 1080p, donde la densidad es **2.0** → la pantalla mide
960×540 dp. Roku trabaja en **píxeles de 1920×1080**. Por tanto:

```
1 dp del Kotlin  =  2 px de Roku
```

| Medida en el Kotlin | En Roku |
|---|---|
| Padding de la navbar: 32 dp horizontal / 16 dp vertical | 64 px / 32 px |
| Radio de tarjeta: 12 dp | 24 px |
| Radio de píldora: 24 dp | 48 px |
| Grosor del borde de foco: 3 dp | **6 px** |
| Alto del preview en modo ventana: 260 dp | 520 px |
| Fade del header: 210 dp | 420 px |
| Subida del fade del EPG: 55 dp | 110 px |
| Alto del fade del EPG: 80 dp | 160 px |

`manifest`: `ui_resolutions=fhd`. Se diseña a 1920×1080 y Roku escala a 720p.

---

## 1. Tokens de marca (`BrandConfig`)

Réplica exacta de `ui/theme/BrandConfig.kt`. **Un solo archivo**, generado por ISP
(ver `MULTI_ISP.md`). Fuera de él, ningún componente define un color.

### Color de marca (cambia por ISP)

| Token | Valor | Uso |
|---|---|---|
| `accent` | de `ENV/config.txt` | Botones activos, progreso, acentos |
| `accentSoft` | `accent` al 20 % de opacidad | **Derivado**, no se define aparte |

### Neutros (fijos, NO cambian por cliente)

| Token | Hex | Uso |
|---|---|---|
| `background` | `#0B0B0D` | Fondo principal, casi negro |
| `surface` | `#161619` | Tarjetas y paneles |
| `surfaceVariant` | `#1F1F23` | Inputs, píldoras inactivas |
| `textPrimary` | `#F5F5F7` | Texto principal |
| `textSecondary` | `#9BA1A6` | Metadatos |
| `textDisabled` | `#5A5F66` | Deshabilitado |
| `pillActive` / `pillActiveText` | `#F5F5F7` / `#0B0B0D` | Píldora de categoría activa (blanca, texto oscuro) |
| `liveNow` | `#E53935` | Rojo del programa en emisión |

### Foco

| Token | Valor | Nota |
|---|---|---|
| `focusOutline` | **blanco puro**, fijo | Deliberadamente **no** usa el color de marca: el foco se ve igual en toda la app, estilo Netflix/YouTube |
| `accentText` | acento mezclado **35 % hacia el blanco** | Texto en color de marca sobre superficies oscuras. Derivado y no crudo porque un acento oscuro (el verde de Oneplay) se lee justo sobre el gris de las celdas y uno claro se lee bien: derivarlo funciona con **cualquier** marca sin ajustar nada por ISP |
| `focusBorderWidth` | 6 px | Grueso para que se note en TV |

### Formas redondeadas

SceneGraph **no sabe dibujar esquinas redondeadas**: `Rectangle` solo hace ángulos rectos. Se
resuelve con el componente `RoundedRect`, un `Poster` sobre una imagen **9-patch** que estira solo
la franja central y conserva las esquinas a cualquier tamaño.

Las texturas se generan en BLANCO (`npm run shapes`) y se tiñen con `blendColor`, así que **dos
imágenes diminutas cubren todos los colores de la app** — 922 bytes la píldora. En un Roku Express,
donde la memoria de texturas escasea, eso evita una textura por cada combinación color×radio.

| Forma | Radio | Se usa en |
|---|---|---|
| `card` | 16 px | Tarjetas, campos, filas de la parrilla, celdas, paneles |
| `pill` | 20 px | Píldoras de categoría, botones, filas del menú de cuenta |

**Pastillas, no cápsulas.** El Kotlin declara 24 dp de radio, pero Compose lo **recorta a la mitad
del lado menor**, así que el radio efectivo allí es mucho menor que el declarado. Copiar el 24 dp
literal (48 px) daba óvalos: las esquinas se comían el lado recto entero. Ajustado mirando la tele.

### Degradados

SceneGraph **no tiene degradados**. Se generan como PNG en el build (`scripts/lib/image.js`), de
2 px de ancho × una fila de píxeles por fila de pantalla, y el `Poster` los estira.

La solución anterior —apilar rectángulos con alfa escalonada— **se veía a bandas en el aparato**:
con 18 escalones cada salto de opacidad se distingue sobre el vídeo. Aquí el salto es de 1/255.

| Degradado | Medida | Paradas de opacidad |
|---|---|---|
| Header | 420 px (210 dp) | 0.88 → transparente |
| EPG | 270 px, desde y=538 | 0 · 0.30 · 0.60 · 0.88 · 1.0 — **no lineal**: se queda claro hasta el 35 % y luego oscurece deprisa, para no tapar el vídeo antes de tiempo |
| **Izquierda** | 1920 px, horizontal | 1.0 en el borde · 0.60 al 40 % · transparente al 80 %. Es lo que hace legible el texto del canal sobre un vídeo claro |

Siguen siendo `Rectangle` los velos a pantalla completa, las bandas de degradado y las barras de
progreso: redondear algo de 4 px de alto no se ve, y un velo de 1920×1080 no tiene esquinas visibles.

### Controles "glass"

Un solo interruptor cambia el aspecto de **todos** los controles (iconos de la navbar, "Mi lista",
pantalla completa, píldoras de categoría):

| Token | Valor | Efecto |
|---|---|---|
| `glassControls` | `true` | Fondo translúcido que deja ver el vídeo detrás |
| `glassAlpha` | `0.45` | Opacidad del vidrio |
| `controlSurface` | `surface` al 45 % (si glass) o `surfaceVariant` (si no) | Fondo del control en reposo |
| `controlSurfaceDisabled` | `surface` al 30 % | Control deshabilitado |

> En Roku no hay desenfoque real de fondo barato. El "glass" se consigue con un `Rectangle` de color
> `surface` y opacidad — **sin blur**. Es la primera desviación aceptada: el Kotlin usa
> `backdropBlur` en algunos puntos; en Roku se sustituye por translucidez plana. Si el resultado no
> convence, la alternativa es un `Poster` con una imagen difuminada pregenerada.

---

## 2. Las pantallas

### 2.1 Intro

Fondo de marca a pantalla completa (`brand_intro`), logo y entrada al login.

### 2.2 Login

Fondo de marca (`brand_login`). Layout partido: marca a un lado, formulario al otro. Campos
**Correo** y **Contraseña** (enmascarada) + botón **Ingresar**. El panel del QR del diseño original
es **decorativo**: el login por QR necesita endpoints que no existen.

**Foco**: Correo → Contraseña → Ingresar, y el camino inverso. Este es el punto donde fallaron los
otros dos ports (teclado atrapando el D-pad); en Roku hay que usar el teclado virtual del sistema
(`Keyboard`/`MiniKeyboard`) y devolver el foco al campo al cerrarlo.

### 2.3 MainScreen — contenedor browse-first

Barra superior + contenido de la pestaña activa.

**TopNavBar** (padding 64 px horizontal / 32 px vertical):
- **Izquierda**: logo de marca (imagen; si falta, texto con el nombre).
- **Centro**: pestañas *Inicio · TV en directo · Eventos · Contenidos*. Cada una se dibuja como
  `ENABLED` / `DISABLED` (gris) / `HIDDEN`, resuelto por switch de marca × backend (§4).
  **Si solo queda una pestaña visible, no se dibuja ninguna** — una sola pestaña no aporta
  navegación.
- **Derecha**: iconos Buscar · Mi lista · Perfil.

**Pestaña de arranque: "TV en directo".** Inicio está deprecado y oculto por defecto.

### 2.4 TV en directo (`LiveScreen`) — la pantalla principal

Modo **inmersivo** (es el activo en el rediseño):

- El **vídeo del canal actual ocupa toda la pantalla de fondo**.
- Encima, translúcido: la información del canal arriba y el EPG abajo.
- El bloque de información ocupa el **60 % del alto** de la pantalla; el EPG (categorías + grilla)
  toma el resto.
- Tres degradados hacen que las capas se acoplen sin cortes:
  - **header**: 420 px de alto, oscurece hasta 0.88 de opacidad bajo la navbar;
  - **fade del EPG**: empieza 110 px antes de que termine el preview y llega a **negro pleno** 160 px
    después, justo donde empiezan las filas de canales (que son sólidas) → la unión no se nota y tapa
    el solapamiento al hacer scroll.

**Información del canal** (`CurrentChannelDisplay`): número, logo, nombre, título del programa,
horario, categoría y barra de progreso. Botón **Mi lista**, y solo ese: el de pantalla completa
desapareció con la pantalla única (§2.5), porque el vídeo ya está siempre a pantalla completa
detrás del overlay.

**CategoryTabs**: píldoras horizontales; la activa es blanca con texto oscuro.

**ChannelGrid**: una fila por canal; cada fila, un número **fijo** de celdas de programa —hasta 3
pasadas (catch-up), la de AHORA, y 1 futura.

**Solo se ven 3 celdas a la vez** y la fila se desplaza en horizontal para llegar al resto. Con las
5 repartidas en el ancho disponible el título se cortaba a la tercera letra. Medidas del rediseño
(1 dp = 2 px): columna de canal 320 px, paso de celda **(1920 − 64·2 − 320) / 3 = 490 px**, celda
88 px de alto, fila 96 px. En reposo la celda de AHORA queda en la posición **central**; al mover
el foco la fila se desplaza **lo mínimo** para traer la celda, nunca se recentra (recentrar movería
toda la parrilla bajo el dedo del usuario). Reglas puras en `tvEpgFirstVisibleColumn` y
`tvEpgScrollTo`, con tests.

**El foco entra en la celda de AHORA**, no en la columna del canal: el usuario llega mirando lo que
se está emitiendo. Igual que el rediseño (`enter = { nowCellFR }`). **No** son celdas de ancho proporcional a la duración.
La ventana es maleable: si no hay datos pasados no se dibuja ninguna columna pasada, y todas las
filas tienen el mismo ancho (las que faltan van vacías) para que la rejilla quede alineada.

La celda de AHORA lleva barra de progreso y **su título va en el color de marca derivado**
(`accentText`), no un fondo de color. El fondo lo pisa el marco de foco, así que la celda perdía su
marca justo al seleccionarla; el texto el foco no lo toca. Las **pasadas con grabación comprobada**
llevan marca de reproducible (▶) — comprobada de verdad, con sonda: el flag `catchup` del backend
miente (`BACKEND-GOTCHAS.md` §3). Lógica en `domain/usecase/EpgGrid.brs`, con tests.

### 2.5 Los dos modos de "TV en directo"

**No hay una pantalla de reproductor aparte.** "TV en directo" es una sola pantalla con dos modos, y
el vídeo **no se interrumpe** al pasar de uno a otro — esa es la razón de ser del diseño.

| Modo | Qué se ve | Qué hacen ↑↓ |
|---|---|---|
| Overlay **visible** | Barra superior, info del canal, categorías y parrilla, sobre el vídeo | Mueven el foco |
| Overlay **oculto** | Solo el vídeo, limpio a pantalla completa | **Zapean** (CU-11) |

Se oculta de tres formas, y las tres hacen lo mismo: con ATRÁS desde las categorías, **a los 2
minutos sin tocar el mando**, o al llegar desde Buscar / Mi lista con un canal pedido.
Vuelve con **OK**. La barra superior se oculta **con** el overlay.

Al zapear con el overlay oculto aparece la **franja del canal** 5 s (`ChannelStrip`), con lo mismo
que la zona superior y calculada igual.

> **El auto-ocultado solo actúa si el reproductor está en `playing`.** Existe para destapar el
> vídeo; sin vídeo detrás solo deja un negro mudo, y el usuario que vuelve no sabe si la app se
> colgó o se quedó sin internet. Regla en `tvCanAutoHideOverlay`, con tests.

### 2.5.b Reproductor de grabaciones (`CatchupPlayer`)

Esta **sí** es una pantalla aparte, y a propósito: tiene controles que el directo no necesita.
Avance y retroceso saltan **una dieciseisava parte de la duración**, no un número fijo de segundos,
para que el salto sea proporcionado en una grabación de 20 minutos y en una de 3 horas. Al abrirla
el directo se **detiene** (no se pausa: pausar no libera el decodificador). Al cerrarla, el directo
se vuelve a **preparar** y la parrilla vuelve a la fila **del canal de la grabación**.

### 2.6 Mi lista · Buscar · Perfil

Pantallas apiladas que abren los iconos de la navbar. Perfil despliega menú con **Perfil ·
Mi Plan · Cambiar contraseña · Cerrar sesión**.

### 2.7 Modales

`AdultPin` (entrada numérica con D-pad), `Premium` ("Pack {sección}"), `Restriction` (IP no
permitida), `Offline` (con botón de reconectar). Todos sobre el mismo fondo translúcido.

### 2.8 Toast de notificaciones

Aviso flotante temporal; se cierra solo a los 5 s.

---

## 3. Reglas de foco (obligatorias)

SceneGraph no tiene navegación espacial: **el foco se mueve a mano**. Ver `arquitectura_flujo.md` §5.

1. Cada pantalla declara su **nodo con foco inicial** y qué pasa en cada borde.
2. **Ningún nodo decorativo es enfocable.** Si no responde a OK, no recibe foco.
3. Al abrir un modal se guarda el nodo enfocado y se restaura al cerrarlo.
4. Al abrir la lista de canales se enfoca **el canal que está en reproducción**, no el primero
   (esto fue un fix explícito en el Kotlin, CU-06).
5. La lista de canales **no da la vuelta** arriba/abajo (coincide con el original); las **categorías
   sí** dan la vuelta en ambos extremos.

---

## 4. Pestañas por cliente

Regla copiada de `TabsResolver.kt`, se replica tal cual:

| Switch de marca | Lo que manda el backend | Resultado |
|---|---|---|
| `false` | lo que sea | **HIDDEN** (override maestro) |
| `true` | presente y con datos | **ENABLED** |
| `true` | presente pero apagada/vacía | **DISABLED** (se dibuja gris) |
| `true` | ausente | **HIDDEN** |

---

## 5. Assets

| Asset | Origen | Nota |
|---|---|---|
| Logo interno | `ENV/logo.png` | **Si falta, NO se dibuja un rectángulo de color**: la app cae al nombre en texto con estilo de marca, igual que el rediseño Kotlin. El logo del ISP ya lleva su nombre dentro, así que cuando hay logo el texto NO se repite |
| Fondo de intro | `brand_intro` | Pantalla completa |
| Fondo de login | `brand_login` | Pantalla completa |
| Iconos y splash del canal | ver `MULTI_ISP.md` | Los pide el `manifest`, con tamaños fijos de Roku |

**Imágenes al tamaño exacto en que se dibujan.** Roku reescala en el dispositivo y en gama baja eso
se paga en memoria y en tirones al hacer scroll.

---

## 6. Desviaciones aceptadas respecto al Kotlin

> Se anotan aquí según aparezcan. Cada una necesita una razón técnica, no una preferencia.

| Desviación | Motivo | Estado |
|---|---|---|
| "Glass" con translucidez plana en vez de blur real | SceneGraph no tiene blur de fondo barato | Aceptada |
| Degradados como PNG, no como nodo | SceneGraph no tiene degradados. Apilar rectángulos con alfa escalonada **se ve a bandas en el aparato** (verificado 2026-10-12): cada escalón es un salto de opacidad visible sobre el vídeo. Se generan en el build, 2 px de ancho × una fila por píxel de alto | Resuelta |
| Sin CH+/CH- para el zapping | El control de Roku no tiene esos botones | Aceptada (`plan_migracion.md` §8.2) |
| Anchos de celda del EPG | Por decidir tras medir en dispositivo | Cerrada: columnas fijas, como el Kotlin (`plan_migracion.md` §8.3) |
| Sin CH+/CH- (solo flechas) | El mando de Roku no tiene esos botones | Aceptada |
| Sin control del buffer del reproductor | Roku no expone los umbrales de buffer que sí ajusta ExoPlayer en el Kotlin. El arranque lo gobierna el firmware | Aceptada |
| La pantalla puede entrar en reposo con el vídeo parado | Roku no tiene API para impedir el salvapantallas; lo suprime solo mientras hay vídeo en marcha | Aceptada |
