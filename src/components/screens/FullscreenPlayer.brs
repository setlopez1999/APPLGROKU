' CU-11 — Zapping a pantalla completa. Ver FullscreenPlayer.xml.
'
' ⚠ Toca el dispositivo: no se ejecuta en `npm test`. La búsqueda del siguiente canal está en
' domain/usecase/Zapping.brs, que sí tiene tests (incluido el crítico: si todos los canales están
' bloqueados devuelve invalid en vez de desbordar la pila, que es lo que hacía el original).

sub init()
    print "[TV] FullscreenPlayer.init"
    m.brand = m.global.brand

    m.infoBar = m.top.findNode("infoBar")
    m.logo = m.top.findNode("logo")
    m.number = m.top.findNode("number")
    m.name = m.top.findNode("name")
    m.programTitle = m.top.findNode("programTitle")
    m.programTime = m.top.findNode("programTime")
    m.status = m.top.findNode("status")

    ' Velo bajo la barra para que el texto se lea sobre cualquier imagen.
    m.top.findNode("infoBg").color = "0x000000B8"
    m.number.color = m.brand.textSecondary
    m.name.color = m.brand.textPrimary
    m.programTitle.color = m.brand.textPrimary
    m.programTime.color = m.brand.textSecondary
    m.status.color = m.brand.liveNow

    m.hideTimer = m.top.findNode("hideTimer")
    m.hideTimer.observeField("fire", "onHideTimer")

    m.channels = m.global.channels
    m.sections = m.global.sections
    if m.channels = invalid then m.channels = []
    if m.sections = invalid then m.sections = []

    m.premiums = []
    userInfo = m.global.session
    if tvHasSession(userInfo) then m.premiums = userInfo.premiumsAllowed

    m.guide = m.global.epg
    m.utcOffset = tvDeviceUtcOffsetSec()
    m.current = invalid
end sub

sub onStartChannel()
    channel = tvFindChannelByCnId(m.channels, m.top.startCnId)
    if channel = invalid then return
    tune(channel)
end sub

' ---- zapping -----------------------------------------------------------------

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if key = "down"
        zap(true)
        return true
    end if

    if key = "up"
        zap(false)
        return true
    end if

    ' Cualquier otra tecla revela la barra de información, como el original.
    if key = "OK" or key = "info"
        showInfo()
        return true
    end if

    ' El ATRÁS no se consume: lo resuelve MainScene sacando esta pantalla de la pila.
    return false
end function

sub zap(goingDown as boolean)
    actual = 0
    if m.current <> invalid then actual = m.current.cnId

    siguiente = tvFindNextChannel(m.channels, actual, goingDown, m.sections, m.premiums)

    ' invalid = ningún canal reproducible en toda la lista. Aquí el original entraba en recursión
    ' infinita; se avisa y se deja el canal actual en marcha.
    if siguiente = invalid
        m.status.text = "No hay más canales disponibles"
        return
    end if

    tune(siguiente)
end sub

sub tune(channel as object)
    print "[TV] zap → "; channel.nombre; " ("; channel.numero; ")"
    if not tvIsPlayable(channel)
        ' Nunca se manda una url vacía al reproductor (docs/BACKEND-GOTCHAS.md §5).
        m.status.text = "Este canal no está disponible en tu plan"
        return
    end if

    m.status.text = ""
    m.current = channel
    m.top.currentCnId = channel.cnId
    m.global.currentCnId = channel.cnId

    video = m.top.videoNode
    if video <> invalid
        applyStreamUserAgent(video)

        content = CreateObject("roSGNode", "ContentNode")
        content.url = channel.streamUrl
        content.streamformat = "hls"
        content.title = channel.nombre

        ' DETENER, no pausar: pausar no libera el decodificador y solo hay uno (§9).
        video.control = "stop"
        video.content = content
        video.control = "play"
        video.visible = true
    end if

    renderInfo()
    showInfo()
end sub

sub applyStreamUserAgent(video as object)
    if GetInterface(video, "ifHttpAgent") = invalid then return
    agent = CreateObject("roHttpAgent")
    agent.AddHeader("User-Agent", tvStreamUserAgent())
    video.setHttpAgent(agent)
end sub

' ---- barra de información ----------------------------------------------------

sub renderInfo()
    if m.current = invalid then return

    programs = tvProgramsForChannel(m.guide, m.current.cnId)
    info = tvBuildChannelInfo(m.current, programs, tvNowSeconds(), m.utcOffset)

    m.logo.uri = info.logo
    m.number.text = Str(info.numero).Trim()
    m.name.text = info.nombre
    m.programTitle.text = info.ahoraTitulo

    if info.tieneAhora
        m.programTime.text = info.ahoraInicio + " - " + info.ahoraFin
    else
        m.programTime.text = ""
    end if
end sub

sub showInfo()
    m.infoBar.visible = true
    ' Se reinicia en cada zap: si no, la barra se esconde mientras el usuario sigue cambiando.
    m.hideTimer.control = "stop"
    m.hideTimer.control = "start"
end sub

sub onHideTimer()
    m.infoBar.visible = false
end sub
