# Trampas de la plataforma Roku — TV-Visor

> **Para qué sirve**: el gemelo de `BACKEND-GOTCHAS.md`, pero de la plataforma. Todo lo que cuesta
> días descubrir con SceneGraph y no se deduce leyendo la documentación.
>
> **Cómo leerlo**: cada punto dice si está **verificado en dispositivo** (con fecha y modelo) o si es
> **conocido / por verificar**. No mezclar: lo verificado es dato duro; lo demás es una hipótesis
> razonable que hay que comprobar antes de construir encima.
>
> **Estado inicial**: nada verificado todavía en dispositivo. Este archivo se llena durante la Fase 0.

---

## 1. HTTPS falla sin el archivo de certificados

**Conocido, por verificar.** En BrightScript, un `roUrlTransfer` sobre HTTPS necesita:

```
xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
xfer.InitClientCertificates()
```

Sin eso, **todas** las llamadas fallan, y no con un mensaje claro: se parecen a un problema de red o
de backend. Es el error nº1 de quien viene de otras plataformas.

**Al implementar**: un único helper en `util/` construye todos los `roUrlTransfer` con los
certificados ya puestos. **Nadie crea uno a mano.**

Relacionado: `BACKEND-GOTCHAS.md` §8 documenta un certificado vencido en `centauro.cd-latam.com` que
tumbó 5 canales que en realidad emitían bien. En Roku eso se verá como un fallo de conexión sin
código HTTP — distinguirlo de un 404 antes de culpar a la señal.

---

## 2. La red en el hilo de render congela el canal

**Conocido.** `roUrlTransfer` síncrono (`GetToString`) bloquea el hilo. En SceneGraph eso congela la
interfaz y, si tarda, el sistema puede matar el canal.

**Regla del proyecto**: toda la red vive en `components/tasks/`, con `AsyncGetToString` +
`roMessagePort`. Ni una excepción.

---

## 3. El foco es manual, no hay navegación espacial

**Conocido.** No existe nada parecido a `SpatialNavigation.js` ni al sistema de foco de Compose. El
foco se mueve llamando a `setFocus(true)` y cada componente decide a quién se lo cede.

Los otros dos ports tropezaron exactamente aquí (botón inalcanzable en tvOS, campo de texto atrapando
el D-pad en Compose). Reglas adoptadas: ver `arquitectura_flujo.md` §5 y `DISENO.md` §3.

---

## 4. Un solo nodo `Video`, y hay que detenerlo de verdad

**Conocido, y coincide con lo ya verificado en Android** (`BACKEND-GOTCHAS.md` §9): el decodificador
es un recurso único. Crear un segundo nodo `Video` para la grabación mientras el vivo sigue vivo es
la forma segura de acabar con pantalla negra.

**Pausar no libera el decodificador.** Hay que `control = "stop"` antes de cargar otro contenido, y
asumir ~1 segundo de reenganche al volver.

---

## 5. El registro son 32 KB para todo el canal

**Conocido, por medir.** `roRegistrySection` tiene un límite total de **32 KB por canal**. El original
guarda el `user_info` completo en `localStorage`; ese JSON de un ISP con muchos canales puede
acercarse al límite.

**Regla propuesta** (a confirmar midiendo con una cuenta grande): en el registro solo lo mínimo
persistente — `deviceId`, email, password cifrado, `rememberMe` y flags. El `UserInfo` completo vive
en memoria y se recarga de `get-web2` al arrancar.

---

## 6. El control de Roku no tiene CH+/CH-

**Verificado por diseño de la plataforma.** El mando estándar tiene: ↑↓←→, OK, Atrás, Inicio, `*`
(Opciones), Replay, y los de transporte en algunos modelos. **No hay botones de canal.**

Consecuencia: del CU-11 del original solo sobrevive el zapping con flechas (que es, además, lo que
hace el rediseño Kotlin). Ver `plan_migracion.md` §8.2.

---

## 7. No hay "salir de la app"

**Conocido.** Devolver `false` en el `onKeyEvent` de la escena raíz al pulsar Atrás hace que el
sistema cierre el canal. No hay diálogo de confirmación como en Samsung/Android, y **no conviene
inventarlo**: rompe la expectativa del usuario de Roku.

---

## 8. No hay bcrypt

**Verificado por la API disponible.** `roEVPDigest` ofrece md5, sha1 y sha256. `roEVPCipher` hace
AES (sirve para el password de sesión). **bcrypt no existe**, y el backend manda `parentlockcode`
como hash bcrypt.

Es el bloqueo funcional nº1 del proyecto. Opciones y recomendación en `plan_migracion.md` §8.1.

---

## 9. El User-Agent del reproductor · **verificar en Fase 0**

`BACKEND-GOTCHAS.md` §1: los servidores de Playcom devuelven **403 a cualquier User-Agent que no
empiece por `APPMOVIL`**, y sin él no hay vídeo ni error que lo explique.

En Android se resuelve poniendo el User-Agent en el cliente HTTP del reproductor (distinto del de la
API). En Roku hay dos vías candidatas y **hay que confirmar cuál funciona en el nodo `Video`**:
cabeceras en el `ContentNode` del stream, o un `roHttpAgent` asociado al nodo.

**Si ninguna funciona, el vídeo de ese ISP no se ve.** Por eso se verifica en la Fase 0, antes de
construir nada encima.

---

## 10. Rendimiento de SceneGraph en gama baja

**Conocido, por medir.** Los dispositivos que ponen los ISP son baratos. Lo que más se paga:

- Crear y destruir nodos durante el scroll (usar listas perezosas con `numRows` acotado).
- Imágenes más grandes de lo que se dibujan (Roku reescala en el dispositivo).
- Trabajo de BrightScript en el hilo de render: BrightScript es **lento**; cualquier bucle sobre
  cientos de canales va a `domain/` y se ejecuta una vez, no en cada redibujado.

---

## 11. La grilla del EPG no sale gratis

**Conocido.** `RowList` y `MarkupGrid` no soportan celdas de ancho proporcional a la duración del
programa, que es justo lo que pide el diseño. Hay que componer la fila a mano o simplificar el
modelo. Decisión abierta en `plan_migracion.md` §8.3 — **decidir midiendo**, no antes.

---

## 12. Herramientas de diagnóstico

```bash
# Consola de depuración (dejar abierta en otra terminal)
telnet <ip-roku> 8085

# Teclas sin tocar el mando (ECP)
curl -d '' http://<ip-roku>:8060/keypress/Down
curl -d '' http://<ip-roku>:8060/keypress/Select
curl -d '' http://<ip-roku>:8060/keypress/Back

# Sideload
npx roku-deploy
```

Y, como en los otros repos: **verificar siempre qué canal está corriendo** antes de interpretar un
log. En el port de Android se perdió un diagnóstico leyendo los logs de otra app
(`BACKEND-GOTCHAS.md` §14).

---

## 14. Rarezas del lenguaje que ya nos mordieron

**Verificado, 2026-09-17**, escribiendo la capa de lógica:

| Qué | Qué pasa |
|---|---|
| `rem` no se puede usar como nombre de variable | `rem` **inicia un comentario** en BrightScript. `rem = a mod b` se traga el resto de la línea y el error que da es "token inesperado" en la línea siguiente, que despista |
| `next` tampoco | Es palabra reservada (`for...next`) |
| `step` tampoco | Es palabra reservada (`for ... to ... step`). Se suma a `rem` y `next` |
| `roArray` **no tiene `Insert()`** | Solo `Push`, `Pop`, `Shift`, `Unshift`, `Delete`, `Append`, `Clear`, `Count`. Para insertar en medio hay que desplazar por índice. Y falla en *ejecución*, no al compilar: "Function Call Operator ( ) attempted on non-function" |
| `Str(n)` mete un espacio delante | Siempre `Str(n).Trim()`. Si no, se cuela en urls y textos |
| El `mod` de un negativo da negativo | Al calcular la hora local con desfase negativo hay que sumar 86400 |
| `global` no se puede usar como variable | Es palabra RESERVADA. El error que da es `Unable to cast "Object" to "Interface"`, que no lo sugiere para nada. Nos costó el primer arranque |
| El `Integer` es de 32 bits | Máximo 2.147.483.647. El `devid` del original es un aleatorio entre 1.000.000.000 y **9.999.999.999**, que NO cabe. Se construye como texto de 10 dígitos, no como número |

Las tres primeras las caza `npm test` en segundos; sin el intérprete en Node se habrían descubierto
en el dispositivo, mucho más caro.

---

## 15. Errores en los que ya caímos

> Vacío al inicio. Se llena con cada diagnóstico equivocado, como se hizo en
> `BACKEND-GOTCHAS.md` §14 — esa tabla ahorró días.

| Conclusión apresurada | Lo que era en realidad |
|---|---|
| — | — |

---

## 16. Los componentes NO ven lo que hay en `pkg:/source/`

**Verificado el 2026-09-17**, con el compilador, al escribir las primeras pantallas.

Lo que hay en `pkg:/source/` está disponible en el **hilo principal** (`main.brs`), pero **no** dentro
de un componente SceneGraph. Cada componente tiene su propio ámbito y debe declarar lo que usa:

```xml
<script type="text/brightscript" uri="pkg:/components/screens/LoginScreen.brs" />
<script type="text/brightscript" uri="pkg:/source/util/Json.brs" />
<script type="text/brightscript" uri="pkg:/source/domain/usecase/SessionRules.brs" />
```

Sin eso da `Cannot find function 'tvXxx'`. Es fácil asumir lo contrario, porque en el hilo principal
sí funciona.

**Consecuencia práctica**: al añadir una llamada nueva a un componente, hay que acordarse de añadir
también su `<script>`. `npm run lint` lo caza al instante — es la razón de correrlo antes de cada
envío al aparato.

---

## 17. Ocultar un nodo NO le quita el foco

**Verificado en el simulador el 2026-09-21**, con el teclado del login.

Al cerrar el teclado se hacía `keyboardLayer.visible = false` y `m.top.setFocus(true)`. **Ninguna de
las dos cosas le quita el foco al nodo `Keyboard`**: seguía invisible pero comiéndose las teclas.
Síntoma desconcertante: tras escribir el correo, las flechas dejaban de funcionar y el siguiente
ATRÁS se escapaba hasta la escena raíz, **que cerraba el canal**.

```brightscript
m.keyboardLayer.visible = false
m.keyboard.setFocus(false)     ' ← esta línea es la que hace falta
m.top.setFocus(true)
```

**Regla general**: al cerrar cualquier capa que haya tomado el foco (teclado, modal, panel), hay que
quitárselo EXPLÍCITAMENTE al nodo que lo tenía, además de ocultarlo. Esto es la versión Roku del
mismo fallo que documentaron en tvOS y en Compose (`arquitectura_flujo.md` §5).

---

## 18. Lo que SÍ funciona (verificado en el simulador, 2026-09-21)

Para no volver a dudar de estas piezas:

| Pieza | Estado |
|---|---|
| `roUrlTransfer` + `SetCertificatesFile` sobre HTTPS | ✅ **200 real contra `oneplay.iptvperu.tv`** |
| `Task` node para la red, fuera del hilo de render | ✅ |
| `roRegistrySection` (leer y escribir) | ✅ |
| Nodo `Keyboard` y captura de texto | ✅ |
| `<script>` de `pkg:/source/` en componentes | ✅ (obligatorios, ver §16) |
| `platform=12` aceptado por el backend | ✅ **login real completo** con cuenta de Oneplay |
| `roEVPCipher` (cifrar/descifrar el password en el registro) | ✅ ida y vuelta: el "recordarme" rellena y el login vuelve a funcionar |
| Aplanado del catálogo sobre datos reales | ✅ 50 canales → **23 reproducibles en 2 categorías**, cuadra con el plan |

**Salvedad**: el simulador (`brs-desktop`, extensión `brs-scenegraph`) implementa SceneGraph de forma
PARCIAL. Lo que funciona aquí es buena señal, pero el render, el foco fino y sobre todo el **vídeo**
hay que confirmarlos en un Roku de verdad.

---

## 19. `AddFields` con `invalid` crea un campo INSERVIBLE

**Verificado en el simulador el 2026-09-21.** El bug más caro de la sesión.

El valor inicial que se le pasa a `AddFields` **define el tipo del campo**. Si se pasa `invalid`, el
campo queda sin tipo utilizable y **las asignaciones posteriores se descartan en silencio**: ni
error, ni aviso, ni nada en el log.

```brightscript
globalNode.AddFields({ session: invalid })   ' ❌ mal
m.global.session = userInfo                  ' se pierde; sigue siendo roInvalid

globalNode.AddFields({ session: {} })        ' ✅ bien: el campo es assocarray
```

Síntoma que tuvimos: el login funcionaba, el catálogo se cargaba… y la guía nunca se pedía, porque
el componente leía `m.global.session` y le llegaba `invalid`. Los campos declarados con tipo
(`channels: []`) funcionaban perfectamente al lado, lo que despista aún más.

**Regla**: todo campo del nodo global se declara con un valor inicial **del tipo correcto**. Para
"todavía no hay valor" se usa el vacío del tipo (`{}`, `[]`, `""`), no `invalid`.

---

## 20. Un token de color que falta se pinta BLANCO

**Verificado en el simulador el 2026-09-21.**

`rectangle.color = <invalid>` no falla: Roku pinta el rectángulo **blanco**. Si encima hay texto
claro, el control desaparece visualmente y parece un problema de diseño, no de datos.

Nos pasó con `controlSurface`, que estaba en el diseño pero **no se generaba** en `BrandConfig`:
los botones de "Mi lista"/pantalla completa y las píldoras de categoría inactivas salían como
rectángulos blancos con el texto invisible.

**Regla**: cualquier token que use un componente tiene que existir en el `BrandConfig` generado.
Al añadir un token al diseño, añadirlo también a `scripts/build-isp.js`.

**Aviso de JavaScript, no de Roku**: `build-isp.js` genera el BrandConfig con un template literal,
así que **un backtick dentro de un comentario BrightScript rompe el generador**. No usar backticks
en el texto que se genera.

---

## 21. El foco en contenedores y listas — dos trampas juntas

**Verificado en el simulador el 2026-09-21.** Costó tres intentos y son el corazón de la navegación.

### a) Un `Group` que recibe el foco SE LO QUEDA

Dar foco a un contenedor no se lo pasa a su hijo activo. `MainScene` se lo daba a `MainScreen`, y
las teclas **no llegaban nunca** a `LiveScreen`. Hay que delegar explícitamente:

```brightscript
sub init()
    ...
    m.top.observeField("focusedChild", "onFocusReceived")
end sub

sub onFocusReceived()
    if m.top.hasFocus() then applyZone()   ' reparte el foco al hijo que toca
end sub
```

### b) Un `MarkupList` con el foco se queda TODAS las flechas verticales

Ni siquiera las propaga estando en la primera fila, así que el foco **no puede salir de la lista** y
el usuario queda atrapado — el mismo fallo que documentaron en el port a tvOS. Con
`vertFocusAnimationStyle="fixedFocusWrap"` es peor todavía, porque da la vuelta al final.

La solución que sí funciona igual en el simulador y en el aparato: **el foco lo tiene el `Group`
contenedor, no la lista.** La lista se desplaza con `jumpToItem` y en los bordes se devuelve
`false` para que la tecla suba:

```brightscript
if key = "up"
    if m.focusIndex <= 0 then return false   ' borde: la tecla sale hacia arriba
    m.focusIndex = m.focusIndex - 1
    m.list.jumpToItem = m.focusIndex
    return true
end if
```

Consecuencia: como la lista no tiene el foco, su `focusPercent` siempre vale 0 y **no sirve para
pintar el marco de selección**. Se pinta desde un campo propio del `ContentNode` de cada fila
(`isSelected`), que el item observa.
