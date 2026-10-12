' CU-15 — Reproductor de grabaciones. Ver CatchupPlayer.xml.
'
' ⚠ Toca el dispositivo: no se ejecuta en `npm test`. El salto de avance/retroceso y el formato de
' tiempo están en domain/usecase/Catchup.brs y util/Time.brs, que sí tienen tests.

sub init()
    print "[TV] CatchupPlayer.init"
    m.brand = m.global.brand

    m.infoBar = m.top.findNode("infoBar")
    m.top.findNode("infoBg").color = "0x000000CC"

    m.logo = m.top.findNode("logo")
    m.channelName = m.top.findNode("channelName")
    m.badge = m.top.findNode("badge")
    m.title = m.top.findNode("title")
    m.elapsed = m.top.findNode("elapsed")
    m.duration = m.top.findNode("duration")
    m.hint = m.top.findNode("hint")
    m.status = m.top.findNode("status")
    m.loading = m.top.findNode("loading")

    m.channelName.color = m.brand.textPrimary
    m.title.color = m.brand.textPrimary
    m.badge.color = m.brand.liveNow
    m.elapsed.color = m.brand.textSecondary
    m.duration.color = m.brand.textSecondary
    m.hint.color = m.brand.textSecondary
    m.status.color = m.brand.textSecondary
    m.loading.color = m.brand.textSecondary

    m.progressTrack = m.top.findNode("progressTrack")
    m.progressFill = m.top.findNode("progressFill")
    m.progressTrack.color = m.brand.surfaceVariant
    m.progressFill.color = m.brand.accent

    m.hideTimer = m.top.findNode("hideTimer")
    m.hideTimer.observeField("fire", "onHideTimer")
    m.tickTimer = m.top.findNode("tickTimer")
    m.tickTimer.observeField("fire", "onTick")
    m.retryTimer = m.top.findNode("retryTimer")
    m.retryTimer.observeField("fire", "onRetryTimer")

    m.url = ""
    m.retryAttempts = 0
end sub

sub onStartCatchup()
    destino = m.top.catchup
    if destino = invalid then return
    if destino.url = "" then return

    m.url = destino.url
    m.top.anchorCnId = destino.cnId

    canales = m.global.channels
    if canales = invalid then canales = []
    canal = tvFindChannelByCnId(canales, destino.cnId)
    if canal <> invalid
        m.logo.uri = canal.imagen
        m.channelName.text = Str(canal.numero).Trim() + " · " + canal.nombre
    end if
    m.title.text = destino.titulo

    video = m.top.videoNode
    if video = invalid then return
    ' Con ámbito: el nodo Video es compartido y vive más que esta pantalla.
    video.observeFieldScoped("state", "onVideoState")

    content = CreateObject("roSGNode", "ContentNode")
    content.url = m.url
    content.streamformat = "hls"
    content.title = destino.titulo
    applyStreamHeaders(content)

    ' DETENER el directo, no pausarlo: pausar no libera el decodificador y solo hay uno, así que
    ' la grabación no arrancaría aunque el servidor respondiera 200 (05-REPRODUCCION).
    video.control = "stop"
    video.content = content
    video.control = "play"
    video.visible = true

    showInfo()
    m.tickTimer.control = "start"
end sub

' El User-Agent es obligatorio también aquí: va contra los mismos servidores de vídeo, y sin él
' algunos responden 403 y la grabación sale negra sin ningún mensaje (05-REPRODUCCION).
sub applyStreamHeaders(content as object)
    content.HttpHeaders = ["User-Agent: " + tvStreamUserAgent()]
end sub

' ---- progreso y controles ----------------------------------------------------

sub onTick()
    video = m.top.videoNode
    if video = invalid then return

    posicion = video.position
    total = video.duration

    m.elapsed.text = tvFormatDuration(posicion)
    if total > 0
        m.duration.text = tvFormatDuration(total)
        m.progressFill.width = Int((1792 * posicion) / total)
    else
        m.duration.text = ""
        m.progressFill.width = 0
    end if
end sub

sub seek(forward as boolean)
    video = m.top.videoNode
    if video = invalid then return

    total = video.duration
    paso = tvCatchupSeekStepSec(total)
    destino = tvCatchupSeekTarget(video.position, paso, forward, total)

    video.seek = destino
    showInfo()
end sub

sub showInfo()
    m.infoBar.visible = true
    m.hideTimer.control = "stop"
    m.hideTimer.control = "start"
end sub

sub onHideTimer()
    m.infoBar.visible = false
end sub

' ---- reintento ---------------------------------------------------------------

sub onVideoState()
    video = m.top.videoNode
    if video = invalid then return

    if video.state = "error"
        m.loading.visible = false
        if not tvShouldRetryPlayback(m.url, m.retryAttempts) then return

        m.retryAttempts = m.retryAttempts + 1
        m.status.text = "Reconectando…"
        m.retryTimer.control = "stop"
        m.retryTimer.control = "start"
        return
    end if

    if video.state = "playing"
        m.loading.visible = false
        m.status.text = ""
        m.retryAttempts = 0
        return
    end if

    if video.state = "buffering" then m.loading.visible = true
end sub

sub onRetryTimer()
    video = m.top.videoNode
    if video = invalid or m.url = "" then return

    content = CreateObject("roSGNode", "ContentNode")
    content.url = m.url
    content.streamformat = "hls"
    content.title = m.title.text
    applyStreamHeaders(content)

    video.control = "stop"
    video.content = content
    video.control = "play"
end sub

' ---- teclas ------------------------------------------------------------------

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if key = "right" or key = "fastforward"
        seek(true)
        return true
    end if

    if key = "left" or key = "rewind"
        seek(false)
        return true
    end if

    if key = "OK" or key = "info"
        showInfo()
        return true
    end if

    ' El ATRÁS no se consume: lo resuelve MainScene sacando esta pantalla de la pila, deteniendo la
    ' grabación y volviendo a preparar el directo.
    return false
end function
