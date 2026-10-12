' Reglas de reproducción, métricas y conectividad: CU-16, CU-18 y el reintento del reproductor.

' ---- CU-16: heartbeat al dashboard -------------------------------------------
'
' Cada 15 s mientras se reproduce. Fire-and-forget: sin callback ni manejo de error, igual que el
' original. Se reinicia cuando el reproductor empieza a sonar (con el cn_id nuevo) y se DETIENE
' mientras el modal de restricción está abierto (player.js:389).

function tvHeartbeatIntervalSec() as integer
    return 15
end function

function tvShouldSendHeartbeat(isPlaying as boolean, isOnline as boolean, restrictionModalOpen as boolean, activeChannel as object, token as string) as boolean
    if not isPlaying then return false
    if not isOnline then return false
    if restrictionModalOpen then return false
    if activeChannel = invalid then return false
    if token = "" then return false
    return true
end function

' ---- CU-18: conectividad -----------------------------------------------------
'
' El modal tiene guard propio: si ya se está mostrando, no se vuelve a mostrar. Sin esto, cada
' comprobación fallida (heartbeat, revalidación, favoritos…) lo relanzaría y robaría el foco.

function tvShouldShowOfflineModal(isOnline as boolean, modalAlreadyShowing as boolean) as boolean
    if isOnline then return false
    return not modalAlreadyShowing
end function

' Qué hacer al recuperar la conexión.
'
' BUG DEL ORIGINAL QUE NO SE REPLICA: en `tryReconnect()` el mensaje de "debes estar conectado" se
' programa SIEMPRE, incluso cuando la reconexión ha ido bien (player.js:564, fuera del `if online`).
' Aquí el mensaje solo existe en la rama offline.
'
'   "retry"       sigue sin conexión → dejar el modal y mostrar el mensaje
'   "reload"      hay conexión pero no hay catálogo → recargar la sesión entera
'   "relaunch"    hay conexión y había un canal → reanudarlo
function tvReconnectAction(isOnlineNow as boolean, hasChannels as boolean, activeChannel as object) as object
    if not isOnlineNow
        return { action: "retry", message: "Para acceder al contenido debes estar conectado a internet" }
    end if

    if not hasChannels or activeChannel = invalid
        return { action: "reload", message: "" }
    end if

    return { action: "relaunch", message: "" }
end function

' ---- Reintento del reproductor -----------------------------------------------
'
' Los streams HLS en vivo se caen solos cada cierto tiempo (docs/BACKEND-GOTCHAS.md §10): hipos del
' CDN, ventanas de vivo muy cortas, discontinuidades. Sin reintento automático el vídeo se queda
' negro para siempre. Patrón del original: esperar ~2 s y volver a preparar la MISMA url — no hay
' failover a otra CDN.

function tvPlayerRetryDelayMs() as integer
    return 2000
end function

' LA REGLA QUE EVITA LA PANTALLA NEGRA PERMANENTE (docs/BACKEND-GOTCHAS.md §5):
' una url vacía NO es invalid — se cuela por los guards ingenuos, el reproductor falla, el reintento
' automático se dispara, vuelve a fallar... y se queda reintentando la misma url vacía para siempre.
' Un canal sin url no se reintenta: no hay nada que reintentar.
' En HLS en vivo los cortes son NORMALES: la ventana de emision se queda atras, el servidor de
' video rota, hay un hipo de red. La respuesta correcta es siempre la misma, sea cual sea el error,
' y NO puede tener tope: con un tope, al agotarlo el canal se queda negro para siempre y el usuario
' tiene que reiniciar el canal. Lo unico que impide reintentar es no tener url.
function tvShouldRetryPlayback(streamUrl as string, attempts as integer) as boolean
    if streamUrl = "" then return false
    return true
end function

' ¿Se puede lanzar este canal? Mismo motivo: nunca mandar una url vacía al reproductor.
function tvIsPlayable(channel as object) as boolean
    if channel = invalid then return false
    if channel.streamUrl = invalid then return false
    return channel.streamUrl <> ""
end function

' ---- Orden de validaciones antes de reproducir -------------------------------
'
' El orden importa y está verificado contra el original (player.js:160-169): premium ANTES que
' adulto, y la restricción por IP la última porque es la única que gasta una llamada de red.
'
'   "premium"     falta el pack → modal de venta
'   "adult"       hay que pedir el PIN
'   "ip"          hay que validar la IP contra el backend
'   "play"        vía libre
'   "unplayable"  sin url: no se intenta
function tvResolveLaunchStep(channel as object, sections as object, premiumsAllowed as object, adultUnlocked as boolean) as string
    if not tvIsPlayable(channel) then return "unplayable"
    if not tvPremiumAllowed(sections, channel.sectionId, premiumsAllowed) then return "premium"

    ' Una vez validado el PIN, los adultos quedan desbloqueados durante la sesión: pedirlo en CADA
    ' selección es insufrible con un mando (afinado así en el port a Kotlin).
    if channel.esAdulto and not adultUnlocked then return "adult"

    if channel.restriccion = 1 then return "ip"
    return "play"
end function

' ---- CU-09: el atasco mudo ---------------------------------------------------
'
' El reintento de `tvShouldRetryPlayback` solo cubre el caso en que el reproductor DICE que hay un
' error. Pero el fallo más común en HLS en vivo no avisa: el canal se queda en `buffering` (o se
' para en seco) y ahí se queda, negro y mudo, sin `errorCode` ni mensaje. Visto en el Roku Express
' el 2026-10-12: el usuario ve el canal pararse y no se recupera solo nunca.
'
' Por eso hace falta un perro guardián aparte: si el reproductor lleva demasiado tiempo FUERA de
' `playing`, se fuerza una recarga aunque nadie haya reportado un error.
'
' 10 s y no menos: un cambio de canal y un bache normal de HLS tardan unos segundos, y recargar
' encima de un buffering que iba a resolverse solo lo único que hace es alargar el corte.
function tvStallTimeoutSec() as integer
    return 10
end function

function tvShouldRecoverFromStall(playerState as string, secondsOutOfPlaying as integer) as boolean
    if playerState = "playing" then return false

    ' El camino de error ya reintenta a los 2 s, que es más rápido: que no compitan los dos.
    if playerState = "error" then return false

    return secondsOutOfPlaying >= tvStallTimeoutSec()
end function
