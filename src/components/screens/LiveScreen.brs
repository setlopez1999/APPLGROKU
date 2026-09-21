' "TV en directo". Ver LiveScreen.xml.
'
' ⚠ Toca el dispositivo: no se ejecuta en `npm test`. Toda la lógica que decide QUÉ mostrar
' (categorías, primer canal, ventana del EPG, info del canal, zapping) está en `domain/` y sí tiene
' tests; aquí solo hay composición, foco y el control del reproductor.

sub init()
    print "[TV] LiveScreen.init"
    m.brand = m.global.brand

    m.display = m.top.findNode("display")
    m.tabs = m.top.findNode("tabs")
    m.grid = m.top.findNode("grid")
    m.status = m.top.findNode("status")
    m.status.color = m.brand.textSecondary

    m.top.findNode("gridBackground").color = m.brand.background

    buildFades()

    m.display.observeField("action", "onDisplayAction")
    m.tabs.observeField("chosenIndex", "onCategoryChosen")
    m.grid.observeField("chosenCnId", "onChannelChosen")

    ' Zonas de foco, de arriba abajo. El foco NUNCA se queda atrapado en una: cada componente deja
    ' pasar arriba/abajo y aquí se decide a dónde va (arquitectura_flujo.md §5).
    m.ZONE_DISPLAY = 0
    m.ZONE_TABS = 1
    m.ZONE_GRID = 2
    m.zone = m.ZONE_GRID

    m.channels = []
    m.filtered = []
    m.currentChannel = invalid
    m.guide = {}
    m.epgWindow = { cells: {}, pastColumns: 0, futureColumns: 0 }
    m.catchupVerified = []
    m.utcOffset = tvDeviceUtcOffsetSec()

    loadCatalog()
    fetchGuide()
    applyZone()
end sub

' Los degradados se imitan apilando rectángulos con alfa escalonada: SceneGraph no tiene gradientes.
sub buildFades()
    ' Header: más oscuro arriba (0.88) y transparente al llegar a 420 px.
    buildFade(m.top.findNode("headerFade"), 0, 420, 0.88, 0.0, 14)

    ' EPG: arranca 110 px antes de que acabe el preview (648) y llega a negro pleno 160 px después,
    ' justo donde empiezan las filas sólidas.
    buildFade(m.top.findNode("epgFade"), 538, 160, 0.0, 1.0, 14)
end sub

sub buildFade(parent as object, y as integer, height as integer, alphaTop as float, alphaBottom as float, steps as integer)
    stepHeight = Int(height / steps)
    for i = 0 to steps - 1
        alpha = alphaTop + ((alphaBottom - alphaTop) * i) / (steps - 1)
        band = parent.createChild("Rectangle")
        band.translation = [0, y + i * stepHeight]
        band.width = 1920
        ' +1 px de solape: si no, se ven costuras finas entre bandas.
        band.height = stepHeight + 1
        band.color = "0x000000" + liveAlphaHex(alpha)
    end for
end sub

function liveAlphaHex(alpha as float) as string
    value = Int(alpha * 255)
    if value < 0 then value = 0
    if value > 255 then value = 255
    digits = "0123456789ABCDEF"
    return Mid(digits, Int(value / 16) + 1, 1) + Mid(digits, (value mod 16) + 1, 1)
end function

' ---- datos -------------------------------------------------------------------

sub loadCatalog()
    m.channels = m.global.channels
    m.sections = m.global.sections
    if m.channels = invalid then m.channels = []
    if m.sections = invalid then m.sections = []

    ' "Todos" como primera píldora, y después las categorías del catálogo.
    names = ["Todos"]
    for each section in m.sections
        names.Push(section.nombre)
    end for
    m.tabs.categories = names
    m.tabs.selectedIndex = 0

    m.filtered = m.channels

    userInfo = m.global.session
    premiums = []
    if userInfo <> invalid then premiums = userInfo.premiumsAllowed

    m.currentChannel = tvGetFirstAllowedChannel(m.channels, m.sections, premiums)
    playCurrent()
    refreshGrid()
end sub

sub fetchGuide()
    userInfo = m.global.session
    if userInfo = invalid then return

    m.guideTask = CreateObject("roSGNode", "ApiTask")
    m.guideTask.observeField("response", "onGuideResponse")
    m.guideTask.request = tvApiRequest(tvApiEpgGuideUrl(m.brand.baseUrl, userInfo.userEmail))
    m.guideTask.control = "RUN"
end sub

sub onGuideResponse()
    response = m.guideTask.response
    if not response.ok then return

    m.guide = tvParseEpgGuide(response.json)

    ' La guía puede llegar con HTTP 200 y el arreglo VACÍO — no se ve en logs ni en códigos de
    ' estado, y la parrilla queda vacía como si fuera un bug de la app (BACKEND-GOTCHAS §7).
    ' Hay que reintentarla POR SU CUENTA, aunque el catálogo no haya cambiado.
    if tvEpgIsEmpty(m.guide)
        m.status.text = "Guía no disponible, reintentando..."
        ' TODO(CU-17): engancharlo al ciclo de refresco con ritmo adaptativo (tvRefreshIntervalSec).
        return
    end if

    m.status.text = ""
    refreshGrid()
    refreshInfo()
end sub

sub refreshGrid()
    now& = tvNowSeconds()
    m.epgWindow = tvBuildEpgWindow(m.guide, m.filtered, now&, m.brand.isCatchupClient, m.catchupVerified, m.utcOffset)

    m.grid.epgWindow = m.epgWindow
    m.grid.channels = m.filtered
    if m.currentChannel <> invalid then m.grid.currentCnId = m.currentChannel.cnId
end sub

sub refreshInfo()
    if m.currentChannel = invalid then return
    programs = tvProgramsForChannel(m.guide, m.currentChannel.cnId)
    m.display.info = tvBuildChannelInfo(m.currentChannel, programs, tvNowSeconds(), m.utcOffset)
end sub

' ---- reproducción ------------------------------------------------------------

sub onVideoNodeReady()
    playCurrent()
end sub

sub playCurrent()
    if m.currentChannel = invalid then return
    video = m.top.videoNode
    if video = invalid then return

    ' Nunca se manda una url vacía al reproductor: con reintento automático se queda reintentando la
    ' misma url vacía para siempre, y eso es pantalla negra permanente (BACKEND-GOTCHAS §5).
    if not tvIsPlayable(m.currentChannel)
        m.status.text = "Este canal no está disponible en tu plan"
        return
    end if

    applyStreamUserAgent(video)

    content = CreateObject("roSGNode", "ContentNode")
    content.url = m.currentChannel.streamUrl
    content.streamformat = "hls"
    content.title = m.currentChannel.nombre

    ' Detener antes de cambiar: pausar NO libera el decodificador, y solo hay uno (§9).
    video.control = "stop"
    video.content = content
    video.control = "play"
    video.visible = true

    refreshInfo()
end sub

' Decisión abierta §8.5 de plan_migracion.md: el servidor de vídeo devuelve 403 a cualquier
' User-Agent que no empiece por APPMOVIL, y sin él TODO el vídeo sale negro sin ningún error que lo
' explique (§1). Aquí se usa la vía del roHttpAgent, con guard por si el nodo no la soporta.
' **HAY QUE CONFIRMARLO EN EL APARATO**: si esta vía no funciona, la alternativa son las cabeceras
' en el ContentNode. Es lo primero que hay que probar con un Roku delante.
sub applyStreamUserAgent(video as object)
    if GetInterface(video, "ifHttpAgent") = invalid
        print "[LiveScreen] el nodo Video no expone ifHttpAgent — revisar el User-Agent APPMOVIL"
        return
    end if

    agent = CreateObject("roHttpAgent")
    agent.AddHeader("User-Agent", tvStreamUserAgent())
    video.setHttpAgent(agent)
end sub

' ---- interacción -------------------------------------------------------------

sub onCategoryChosen()
    index = m.tabs.chosenIndex
    m.tabs.selectedIndex = index

    if index = 0
        m.filtered = m.channels
    else
        m.filtered = tvChannelsForCategory(m.sections, index - 1)
    end if

    refreshGrid()
end sub

sub onChannelChosen()
    channel = tvFindChannelByCnId(m.channels, m.grid.chosenCnId)
    if channel = invalid then return

    ' TODO(CU-14/15): aquí va el paso por tvResolveLaunchStep (premium → adulto → IP). El PIN
    ' parental está bloqueado hasta resolver lo de bcrypt (plan_migracion.md §8.1).
    m.currentChannel = channel
    playCurrent()
    refreshGrid()
end sub

sub onDisplayAction()
    if m.display.action = "fullscreen" then m.top.requestFullscreen = true
    ' TODO(CU-08): "mylist" cuando esté cableado el repositorio de favoritos.
end sub

' ---- foco --------------------------------------------------------------------

sub applyZone()
    m.display.barFocused = (m.zone = m.ZONE_DISPLAY)
    m.tabs.barFocused = (m.zone = m.ZONE_TABS)
    m.grid.gridFocused = (m.zone = m.ZONE_GRID)

    if m.zone = m.ZONE_DISPLAY then m.display.setFocus(true)
    if m.zone = m.ZONE_TABS then m.tabs.setFocus(true)
    if m.zone = m.ZONE_GRID then m.grid.setFocus(true)
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if key = "down"
        if m.zone < m.ZONE_GRID
            m.zone = m.zone + 1
            applyZone()
            return true
        end if
        return false
    end if

    if key = "up"
        if m.zone > m.ZONE_DISPLAY
            m.zone = m.zone - 1
            applyZone()
            return true
        end if
        ' Desde arriba del todo el foco sale hacia la barra superior: lo resuelve MainScreen.
        return false
    end if

    ' Zapping con ↑↓ solo en pantalla completa. El mando de Roku no tiene CH+/CH-
    ' (docs/ROKU-GOTCHAS.md §6), así que aquí las flechas son para navegar.
    return false
end function

' ---- tiempo ------------------------------------------------------------------

function tvNowSeconds() as longinteger
    date = CreateObject("roDateTime")
    return date.AsSeconds()
end function

' Desfase horario del aparato, en segundos. Las funciones de `util/Time.brs` lo reciben como
' parámetro justo para que el cálculo sea puro y testeable.
function tvDeviceUtcOffsetSec() as integer
    utc = CreateObject("roDateTime")
    utcSeconds = utc.AsSeconds()

    local = CreateObject("roDateTime")
    local.ToLocalTime()
    return Int(local.AsSeconds() - utcSeconds)
end function
