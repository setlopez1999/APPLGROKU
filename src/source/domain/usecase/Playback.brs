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
function tvShouldRetryPlayback(streamUrl as string, attempts as integer, maxAttempts = 3 as integer) as boolean
    if streamUrl = "" then return false
    if attempts >= maxAttempts then return false
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
