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
| `accent` | de `brand.json` | Botones activos, progreso, acentos |
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
| `focusBorderWidth` | 6 px | Grueso para que se note en TV |

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
horario, categoría y barra de progreso. Botones **Mi lista** y **pantalla completa**.

**CategoryTabs**: píldoras horizontales; la activa es blanca con texto oscuro.

**ChannelGrid**: filas de canales × columnas de tiempo. Las celdas **pasadas** con grabación
disponible llevan marca de reproducible (▶). Ver `plan_migracion.md` §8.3 sobre cómo dibujar los
anchos.

### 2.5 Pantalla completa (`FullscreenPlayer`)

Vídeo a pantalla completa. **↑↓ hacen zapping.** Encima pueden aparecer los modales (parental,
premium, restricción, offline). El mismo reproductor sirve para el catch-up, con la URL de la
grabación en vez de la del vivo.

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
| Logo interno | `brands/<isp>/images/brand_logo.png` | Si falta, fallback a texto con el nombre |
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
| Sin CH+/CH- para el zapping | El control de Roku no tiene esos botones | Aceptada (`plan_migracion.md` §8.2) |
| Anchos de celda del EPG | Por decidir tras medir en dispositivo | **Abierta** (`plan_migracion.md` §8.3) |
