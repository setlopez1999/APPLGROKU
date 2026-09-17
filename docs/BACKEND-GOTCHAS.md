# Trampas del backend y del streaming — TV-Visor

> **Para qué sirve**: todo lo que NO se deduce leyendo la API ni el código, y que cuesta días
> descubrir en producción. Es **agnóstico del lenguaje**: sirve igual para Kotlin, Swift/tvOS,
> React Native o lo que venga. Si vas a arrancar la app en otra plataforma, lee esto ANTES.
>
> **Cómo leerlo**: cada punto dice si está **verificado en producción** (con fecha y contra qué ISP)
> o si viene **documentado del repo original**. No mezclar: lo verificado es dato duro, lo demás
> puede haber cambiado.
>
> **Última verificación**: 2026-09-17 contra Oneplay (`oneplay.iptvperu.tv`) y Playcom
> (`playcom.trapemn.tv`).

---

## 1. El servidor de video exige un User-Agent concreto

**Verificado.** Los servidores de video de Playcom/trapemn (puerto `:1936`) devuelven **403 a
cualquier User-Agent que no empiece con `APPMOVIL`**. Sin eso, *todo* el video sale negro y no hay
ningún error que lo explique: el manifiesto simplemente no llega.

```
User-Agent: APPMOVIL-androidtv
```

- Oneplay **no** lo exige, pero mandarlo siempre es seguro para ambos.
- La API (`:443`, `get-web2`, `get-epgguide`) es abierta, **no** pide User-Agent. Solo el video.
- La app móvil original manda `APPMOVIL-{devid}`.

**Al portar**: configurar el User-Agent en el cliente HTTP **del reproductor**, no en el de la API.
Son dos clientes distintos y es fácil ponerlo en el que no es.

---

## 2. La URL de catch-up NO se recibe: se construye

**Verificado.** Escaneamos en profundidad **todas** las claves de los cuatro endpoints
(`get-web2` y `get-epgguide`, en los dos ISP). **Ningún endpoint devuelve una URL de grabación.**
Los únicos campos relacionados son `url` (el vivo) y `catchup` (un entero 0/1).

La app la arma sola, a partir de la URL del vivo:

```
url del vivo:   https://host:1936/directorio/canal.stream/playlist.m3u8
grabación:      https://host:1936/directorio/canal.stream/playlist_dvr_range-{inicioSeg}-{duracionSeg}.m3u8
                                                                   └─ se inserta ANTES del .m3u8
```

- `inicioSeg` = `fecha_ini` del programa (epoch en **segundos**)
- `duracionSeg` = `fecha_fin - fecha_ini` (también en segundos)
- Fórmula tomada de la app móvil (`app-mobile-v3 player_screen.dart`)

**La consecuencia es la regla más importante de todo este documento:**

> La grabación **solo puede existir en el mismo directorio que el vivo**. No hay ningún campo donde
> el backend pueda mandar una segunda ruta. Si el directorio del vivo no graba, no hay catch-up
> posible para ese canal, y la app no puede hacer nada al respecto.

---

## 3. El flag `catchup` miente

**Verificado en los dos ISP.** El flag sale de la base de datos del dashboard, lo pone un humano, y
**nadie lo valida contra el servidor de video**. Resultado: hay canales marcados con `catchup: 1`
cuyo directorio no graba nada y devuelve **404**.

El patrón es por tipo de directorio:

```
GRABAN              transcoderip/ · transcoderip2/ · transcoder2/ · nacionales_pe2/
NO GRABAN           failover-SRT/ · artemisa2/ · principal3/ · cluster_alpha/ping_relay_*
                    (son relays y failovers: flujos de paso, sin DVR configurado)
```

Medición del 2026-09-14:

| ISP | Marcados | Con grabación real |
|---|---|---|
| Playcom | 24 | 21 |
| Oneplay | 4 | 1 (y ese con la señal caída) |

**Es de los dos ISP, no de uno.** Playcom también tiene marcados que fallan (America TV, El Nueve,
FOX Sports 3).

**Al portar**: no confíes en el flag para dibujar el botón de reproducir. Hay que **sondear** la URL
de grabación y cachear el resultado. Es **binario** (ver punto 4), así que basta una sonda por canal.

---

## 4. El DVR es binario, no es cuestión de ventana de tiempo

**Verificado.** Un error fácil es pensar "el 404 es porque pedí una hora que ya se borró". No:

- Los canales que fallan devuelven **404 igual a los 5 minutos que a las 8 horas atrás**.
- Los que graban responden **a cualquier rango**, incluidas 8 horas atrás.
- La **duración** tampoco importa: probamos el mismo inicio con 10, 30, 60, 90 y 110 minutos —
  todos 200.

Por eso una sola sonda (p. ej. 10 minutos atrás, 60 segundos de duración) es representativa y se
puede cachear mientras viva el proceso.

**El caso intermedio que sí existe** y que un chequeo por código HTTP no detecta:

> El manifiesto maestro del DVR responde **200** pero la **chunklist viene vacía, sin segmentos**.
> Significa que el directorio *sí* tiene DVR configurado, pero **no hay nada grabado** — casi
> siempre porque la señal de origen del canal está caída y no entra nada que grabar.
> (Verificado con América TV de Oneplay, 2026-09-14.)

---

## 5. El plan del cliente llega como URLs vacías

**Verificado.** El backend devuelve **todos** los canales del ISP, incluidos los que el cliente **no**
tiene contratados. Los que están fuera del plan llegan con:

```json
{ "cn_id": 123, "nombre": "Canal X", "numero": 45, "imagen": "https://...", "url": "" }
```

Con nombre, número y logo — pero `url` vacía. Y es **por categoría completa, todo o nada**:

```
Plan A (23 canales)
  Nacionales   17 canales, 17 con url   ← en el plan
  Musicales     6 canales,  6 con url   ← en el plan
  Deportes      4 canales,  0 con url   ← fuera
  Cine          4 canales,  0 con url   ← fuera
  ...
  TOTAL        50 canales, 23 con url   ← cuadra exacto con planes[].cantidad_canales
```

**Al portar, dos cosas obligatorias:**

1. **Filtrar los canales sin url**, y con ellos las categorías que quedan vacías. Si no, dibujas
   pestañas que al abrirlas no reproducen nada.
2. **Nunca intentar reproducir una url vacía.** Una cadena vacía no es `null`: pasa los guards
   ingenuos, el reproductor falla, y si tienes reintento automático se queda **reintentando la misma
   url vacía para siempre** — pantalla negra permanente.

**Ojo con multi-CDN**: cuando está activo, la url final es `multiCdnUrl + short_link`. Un canal con
`url` vacía **sí puede ser reproducible** por esa vía. El filtro debe evaluar la **url ya resuelta**,
no la cruda, o borrarás canales válidos.

---

## 6. Los campos del backend aparecen y desaparecen en caliente

**Verificado el 2026-09-09/10**, observado en vivo durante un día de trabajo del equipo de backend:

```
11:13   57 canales, 0 sin url, sin campo `catchup`, sin `plan`/`planes`
17:14   aparece `catchup` en 4 canales
19:06   58 canales, 27 sin url  ← empiezan a aplicar planes
09:58   57 canales, 57 SIN url  ← todo roto
10:30   aparecen `plan` y `planes`; las urls vuelven; quedan 5 sin url
```

También vimos aparecer y desaparecer un canal de prueba (`TLNOVELAS`) y una categoría `prueba`.

**Al portar**: la app tiene que **degradar con elegancia y recuperarse sola**. En concreto:

- Que falte un campo no puede romper el parseo (ignorar claves desconocidas, valores por defecto).
- Re-consultar periódicamente y **reconstruir solo si algo cambió de verdad**, para no interrumpir
  la reproducción ni mover el foco.
- Si el estado está degradado (sin canal reproducible, o sin guía), **reintentar más seguido** hasta
  engancharse, y relajar el ritmo al recuperarse.

---

## 7. Hay DOS fuentes de EPG y no son la misma

**Verificado.**

| Fuente | Contenido |
|---|---|
| `epg[]` **dentro** de `get-web2` | Suele venir **casi vacío** (6 de 57 canales en Oneplay) |
| `api/get-epgguide` (endpoint aparte) | La guía completa — **esta es la que alimenta la grilla** |

Y una trampa concreta:

> `get-epgguide` puede devolver **HTTP 200 con un arreglo vacío `[]`** (2 bytes). No es un error que
> se vea en logs ni en códigos de estado. La grilla queda vacía y parece un bug de la app.

**Al portar**: si la guía está vacía, hay que **reintentar ese endpoint por su cuenta**, aunque la
lista de canales no haya cambiado. Si solo refrescas la guía cuando cambian los canales, te puedes
quedar con la grilla vacía indefinidamente.

---

## 8. Mismo servidor, distintos hostnames — y certificados que vencen

**Verificado el 2026-09-14.** Varios hostnames apuntan a la **misma IP**:

```
oneplay.iptvperu.tv     →  191.98.169.6
centauro.cd-latam.com   →  191.98.169.6   (el mismo servidor)
```

Y nos encontramos con esto:

```
atvplus vía centauro.cd-latam.com:1936   →  falla  (SEC_E_CERT_EXPIRED)
atvplus vía oneplay.iptvperu.tv:1936     →  200    (misma ruta, mismo contenido)
```

**El certificado TLS de `centauro.cd-latam.com` estaba vencido.** 5 canales parecían "caídos" y en
realidad emitían perfecto: el reproductor cortaba en el handshake TLS. El mismo host en el puerto
**1935 (sin TLS) sí funcionaba**, lo que despista aún más.

**Al portar**: cuando un canal no reproduce, distinguir estos tres casos antes de culpar a la señal:

1. **Fallo de TLS** (no hay código HTTP, la conexión ni se establece) → certificado o SNI.
2. **404** → la ruta no existe o el stream no está publicado.
3. **200 pero sin segmentos** → el directorio existe pero no hay material.

Un chequeo que solo mire "¿responde 200?" confunde los tres.

---

## 9. Un solo decodificador de video por equipo

**Verificado en TV JVC SA 2K, 2026-09-14.** Este es un problema de **plataforma**, no de backend,
pero muerde igual en cualquier lenguaje.

Estas TVs de gama baja tienen **un solo decodificador H.264 disponible**. Si tienes dos
reproductores instanciados a la vez (por ejemplo, el del vivo de fondo y el de la grabación encima),
el segundo **no consigue decodificador** y muere:

```
DecoderInitializationException: Decoder init failed: OMX.MS.AVC.Decoder
MediaCodec$CodecException: error 0xfffffff4   (recursos insuficientes)
```

Y la trampa fina:

> **Pausar el primer reproductor NO libera el decodificador.** Corta el audio y engaña, pero el
> códec sigue reservado. Hay que **detenerlo** (`stop()` o equivalente), que sí lo suelta.

Coste: al volver, el primer reproductor queda en estado inactivo y hay que **volver a prepararlo**
(un simple "play" no lo reanuda). Se nota como ~1 segundo de reenganche, y es inevitable.

**Al portar**: si la plataforma destino es hardware limitado (Fire TV, cajas baratas, tvOS viejo),
asumir **un solo stream de video a la vez** y liberar de verdad antes de abrir otro.

---

## 10. Rarezas del protocolo de streaming

**Verificado.**

- **LL-HLS mal declarado**: Latina (Oneplay) manda etiquetas de baja latencia (`EXT-X-PART`,
  `EXT-X-PRELOAD-HINT`, `EXT-X-SERVER-CONTROL`) pero declara `#EXT-X-VERSION:3`, que no las soporta.
  Algunos reproductores se atragantan.
- **Ventanas de vivo muy cortas**: algunas chunklists traen solo 2-4 segmentos completos (~25s).
  Conviene bajar el buffer mínimo para que el zapping arranque rápido, en vez de dejar los valores
  por defecto pensados para VOD.
- **Resoluciones mezcladas**: hay canales a 1080p y otros a 720p, con perfiles distintos
  (`avc1.42C028` baseline vs `avc1.640020` high). Los cambios de formato reinician el decodificador.
- **Discontinuidades**: los streams con `failover` traen `EXT-X-DISCONTINUITY`. Hay que tolerarlas
  sin morir.
- **Los streams HLS en vivo se caen solos** cada cierto tiempo (`BehindLiveWindowException`, hipos de
  CDN). **Hace falta reintento automático** o el video se queda negro para siempre. Patrón usado:
  ante error, esperar ~2s y volver a preparar.

---

## 11. Contrato de la API — detalles que no se deducen

**Documentado en el repo original y verificado.**

| Detalle | Realidad |
|---|---|
| `api/delete-favorite` | Es **POST**, no DELETE |
| `api/desvincular` | **Sin body**: `POST api/desvincular?token={token}` como query param |
| `api/channel-allowed-ip` | El body real es `{ip, cn_id}` |
| `platform` | `3` = Android TV · `11` = Fire TV |
| `user_id` | Llega como **número en unos ISP y como texto en otros** — hay que tolerar ambos |
| Contraseña | El backend la exige **en texto plano en CADA llamada a `get-web2`**, no solo en el login |
| `deviceId` / `devid` | **Nunca fue una MAC**: es un número aleatorio de 10 dígitos que se persiste |
| Heartbeat | Cada **15 segundos** mientras reproduce |
| Revalidación de sesión | Cada **60 segundos** |

**Sobre la contraseña**: como se necesita en cada refresco, hay que guardarla cifrada **durante toda
la sesión activa**, independientemente del checkbox "recordarme". Son dos conceptos distintos con
ciclos de vida distintos.

---

## 12. Endpoints en uso

```
api/get-web2        POST   Login, sesión, plan, canales, categorías, urls, premiums, catchup
                           Se re-llama periódicamente (plan/canales frescos)
api/get-epgguide    POST   Guía de programación (alimenta la grilla y el catch-up)
api/get-favorites   POST   Mi lista
api/add-favorite    POST   Agregar
api/delete-favorite POST   Quitar (POST, no DELETE)
api/dashboard       POST   Heartbeat cada 15s
api/channel-allowed-ip POST Restricción por IP
api/desvincular     POST   Cerrar sesión del dispositivo

host:1936           GET    HLS en vivo y DVR — exige User-Agent APPMOVIL-*
```

Estructura de `get-web2` (los canales vienen anidados en tres niveles):

```
get-web2
└── sections[]          ← categorías raíz
    └── sections[]      ← secciones reales (Nacionales, Musicales…)
        └── canales[]   ← los canales
```

Objeto de canal completo:

```json
{
  "cn_id": 2041, "nombre": "Nativa", "numero": 1,
  "imagen": "https://.../logo.png",
  "premium": 0, "adulto": 0, "catchup": 0, "cdn": 1,
  "url": "https://host:1936/directorio/canal.stream/playlist.m3u8",
  "epg": [], "wms": 0
}
```

Raíz de `get-web2`: `user`, `user_id`, `user_email`, `token`, `parentlockcode`, `premiumsallowed`,
`plan`, `planes[]`, `email_soporte`, `fono_soporte`, `whatsapp`, `enabledvod`, `sections[]`.

---

## 13. Cómo diagnosticar sin instalar la app

**Lo que más tiempo ahorra.** Se puede verificar casi todo desde la terminal:

```bash
# ¿la cuenta recibe canales y con qué plan?
curl -s -X POST "https://{host}/api/get-web2?user={email}&pass={pass}&devid=test&platform=3"

# ¿la guía llega? (ojo: puede dar 200 con [] )
curl -s -X POST "https://{host}/api/get-epgguide?user={email}"

# ¿el vivo responde?
curl -A "APPMOVIL-androidtv" "{url_del_canal}"

# ¿la ruta graba? (insertar _dvr_range antes del .m3u8)
curl -A "APPMOVIL-androidtv" "{url_sin_m3u8}_dvr_range-{epoch_inicio}-600.m3u8"
```

**Pero un 200 no basta.** Para saber si un canal *realmente entrega video* hay que recorrer la cadena
completa, igual que el reproductor:

1. Manifiesto maestro responde **y declara un códec de video** (`avc1`/`hvc1`) con resolución
2. Se resuelve la variante y su chunklist **tiene segmentos**
3. Se descarga el primer segmento: **trae bytes** y es **MPEG-TS válido** (byte `0x47` cada 188)

En el repo Kotlin esto está automatizado en `StreamPlaybackAuditTest` (a demanda con
`-DauditStreams=true`), y da un reporte por terminal de los N canales, vivo y grabación. **Portar ese
test a la nueva plataforma es de lo primero que conviene hacer**: convierte "está en negro, no sé por
qué" en una tabla con la causa exacta, sin tocar el equipo.

**Límite honesto de ese test**: verifica que el stream **entrega video decodificable**, no que la
pantalla lo pinte. Que el decodificador de hardware acepte el formato (punto 9) solo se comprueba en
el equipo real.

---

## 14. Errores de diagnóstico en los que ya caímos

Para que no se repitan:

| Conclusión apresurada | Lo que era en realidad |
|---|---|
| "El canal está caído" | Certificado TLS vencido en ese hostname; la señal estaba perfecta |
| "El catch-up no funciona en ningún lado" | Eran **dos** problemas sumados: rutas sin DVR **y** el decodificador ocupado |
| "El 404 es por la ventana de tiempo" | Es binario: la ruta graba o no graba, da igual el rango |
| "El backend está roto, no manda urls" | Estaba aplicando el plan del cliente: fuera del plan → url vacía |
| "El DVR responde 200, entonces funciona" | Respondía 200 con la chunklist **vacía** |
| "Pausé el reproductor, ya liberé recursos" | Pausar no suelta el decodificador; hay que detener |
| "Este error de ExoPlayer es de la app que estoy probando" | Era **otra app** del mismo paquete corriendo de fondo — **verificar siempre el PID** |

---

## 15. Checklist para arrancar en otra plataforma

1. Cliente HTTP del **reproductor** con `User-Agent: APPMOVIL-*` (separado del de la API)
2. Parseo tolerante: ignorar claves desconocidas, valores por defecto en todo
3. **Filtrar canales sin url** y las categorías que quedan vacías
4. **Nunca** reproducir una url vacía
5. Catch-up: construir la url desde la del vivo **y sondear** antes de ofrecerlo
6. Dos fuentes de EPG: usar `get-epgguide`, y reintentarla por su cuenta si viene vacía
7. Refresco periódico que **solo reconstruye si algo cambió**, con ritmo adaptativo si está degradado
8. Un solo reproductor de video a la vez; **detener**, no pausar, antes de abrir otro
9. Reintento automático ante error de HLS (los streams en vivo se caen solos)
10. Guardar la contraseña cifrada mientras dure la sesión (el backend la pide en cada refresco)
11. Portar el test de auditoría de reproducción **desde el principio**

---

## Referencias

- `app-lg/docs/API.md` — endpoints y contratos
- `app-lg/docs/cu/MODELS.md` — modelos de datos
- `app-lg/docs/cu/STATE.md` — estado global y ciclo de vida
- `app-lg/docs/USE-CASES.md` — los 20 casos de uso funcionales
- `app-lg/docs/cu/CU-01..20` — cada caso a detalle (versión agnóstica, del original JS)
