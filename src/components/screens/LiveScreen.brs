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
    m.grid.observeField("chosenCatchup", "onCatchupChosen")

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
    m.favoriteIds = []
    m.adultUnlocked = false
    m.deviceIp = ""
    m.pendingChannel = invalid
    m.utcOffset = tvDeviceUtcOffsetSec()

    loadCatalog()
    fetchGuide()
    fetchFavorites()
    applyZone()

    ' Igual que MainScreen: si esta pantalla recibe el foco, lo delega en su zona activa
    ' (docs/ROKU-GOTCHAS.md §21).
    m.top.observeField("focusedChild", "onFocusReceived")
end sub

sub onFocusReceived()
    if m.top.hasFocus() then applyZone()
end sub

' Los degradados se imitan apilando rectángulos con alfa escalonada: SceneGraph no tiene gradientes.
sub buildFades()
    ' DESVIACIÓN respecto al Kotlin, decidida al verlo en pantalla (2026-09-21): allí el velo del
    ' header se apaga del todo a los 420 px. Aquí el texto del canal y los botones quedaban sobre
    ' vídeo crudo y, con una imagen clara de fondo, no se leían. El velo ya no baja de 0.35: cubre
    ' todo el bloque de info y enlaza sin salto con el de la parrilla.
    buildFade(m.top.findNode("headerFade"), 0, 538, 0.88, 0.35, 18)

    ' De ahí a negro pleno, justo donde empiezan las filas sólidas de la parrilla.
    buildFade(m.top.findNode("epgFade"), 538, 160, 0.35, 1.0, 14)
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
    if tvHasSession(userInfo) then premiums = userInfo.premiumsAllowed

    m.currentChannel = tvGetFirstAllowedChannel(m.channels, m.sections, premiums)
    if m.currentChannel <> invalid
        print "[TV] primer canal permitido: "; m.currentChannel.nombre; " ("; m.currentChannel.numero; ")"
    else
        print "[TV] NINGUN canal reproducible"
    end if
    playCurrent()
    refreshGrid()
end sub

sub fetchGuide()
    userInfo = m.global.session
    if not tvHasSession(userInfo) then return

    m.guideTask = CreateObject("roSGNode", "ApiTask")
    m.guideTask.observeField("response", "onGuideResponse")
    m.guideTask.request = tvApiRequest(tvApiEpgGuideUrl(m.brand.baseUrl, userInfo.userEmail))
    m.guideTask.control = "RUN"
end sub

sub onGuideResponse()
    response = m.guideTask.response
    print "[TV] guia: ok="; response.ok; " http="; response.statusCode; " error="; response.error
    if not response.ok then return

    m.guide = tvParseEpgGuide(response.json)
    m.global.epg = m.guide

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
    probeCatchup()
end sub

' El catalogo cambio de verdad (la revalidacion ya lo ha comprobado). Se repintan categorias y
' parrilla, y se decide que hacer con lo que esta sonando SIN cortarlo si no hace falta.
sub onCatalogVersion()
    m.channels = m.global.channels
    m.sections = m.global.sections
    if m.channels = invalid then m.channels = []
    if m.sections = invalid then m.sections = []

    nombres = ["Todos"]
    for each section in m.sections
        nombres.Push(section.nombre)
    end for
    m.tabs.categories = nombres
    m.filtered = m.channels
    m.tabs.selectedIndex = 0

    urlActual = ""
    if m.currentChannel <> invalid then urlActual = m.currentChannel.streamUrl

    decision = tvResolveAfterRefresh(m.currentChannel, urlActual, m.channels, m.sections, premiumsActuales())
    print "[TV] tras revalidar: "; decision.action

    if decision.action = "keep"
        m.currentChannel = decision.channel
        refreshGrid()
        refreshInfo()
        refreshFavoriteState()
        return
    end if

    if decision.action = "none" then return

    ' "reload" (la url cambio), "switch" (el canal ya no existe) o "blocked" (se perdio el premium)
    if decision.action = "blocked"
        m.status.text = "Este canal ya no esta incluido en tu plan"
    end if

    if decision.channel <> invalid
        m.currentChannel = decision.channel
        playCurrent()
    end if
    refreshGrid()
end sub

function premiumsActuales() as object
    userInfo = m.global.session
    if not tvHasSession(userInfo) then return []
    return userInfo.premiumsAllowed
end function

' ---- catch-up ----------------------------------------------------------------
'
' El flag del backend no basta: hay que SONDEAR (docs/BACKEND-GOTCHAS.md 3). Hasta que la sonda
' responda, ningun canal cuenta como reproducible y no se dibuja el play.

sub probeCatchup()
    if not m.brand.isCatchupClient then return

    marcados = []
    for each channel in m.channels
        if channel.catchup = 1 then marcados.Push(channel)
    end for
    if marcados.Count() = 0 then return

    m.probeTask = CreateObject("roSGNode", "CatchupProbeTask")
    m.probeTask.observeField("verifiedIds", "onCatchupProbed")
    m.probeTask.channels = marcados
    m.probeTask.control = "RUN"
end sub

sub onCatchupProbed()
    m.catchupVerified = m.probeTask.verifiedIds
    ' Se reconstruye la ventana: ahora ya se sabe en que celdas se puede dibujar el play.
    refreshGrid()
end sub

sub onCatchupChosen()
    destino = m.grid.chosenCatchup
    if destino = invalid then return
    if destino.url = "" then return
    m.top.requestCatchup = destino
end sub

' ---- CU-13: restriccion por IP -----------------------------------------------
'
' Solo para los canales con `restriccion = 1`. Es la ultima validacion porque es la unica que gasta
' una llamada. El body real es {ip, cn_id}, verificado en el original.

sub validateIpAndPlay(channel as object)
    m.pendingChannel = channel

    m.ipTask = CreateObject("roSGNode", "ApiTask")
    m.ipTask.observeField("response", "onIpResponse")
    peticion = tvApiRequest(tvApiChannelAllowedIpUrl(m.brand.baseUrl), "POST", tvApiChannelAllowedIpBody(m.deviceIp, channel.cnId))
    m.ipTask.request = peticion
    m.ipTask.control = "RUN"
end sub

sub onIpResponse()
    canal = m.pendingChannel
    m.pendingChannel = invalid
    if canal = invalid then return

    ' 403 = esta IP no puede ver el canal.
    if m.ipTask.response.statusCode = 403
        m.top.blockedReason = "ip"
        return
    end if

    m.currentChannel = canal
    playCurrent()
    refreshGrid()
end sub

' ---- favoritos (CU-08 / CU-09) -----------------------------------------------

sub fetchFavorites()
    userInfo = m.global.session
    if not tvHasSession(userInfo) then return

    m.favTask = CreateObject("roSGNode", "ApiTask")
    m.favTask.observeField("response", "onFavoritesResponse")
    m.favTask.request = tvApiRequest(tvApiGetFavoritesUrl(m.brand.baseUrl, userInfo.userEmail))
    m.favTask.control = "RUN"
end sub

sub onFavoritesResponse()
    response = m.favTask.response
    if not response.ok then return

    m.favoriteIds = tvParseFavoriteIds(response.json)
    m.global.favoriteIds = m.favoriteIds
    print "[TV] favoritos: "; m.favoriteIds.Count()
    refreshFavoriteState()
end sub

sub refreshFavoriteState()
    if m.currentChannel = invalid then return
    m.display.isFavorite = tvIsFavorite(m.favoriteIds, m.currentChannel.cnId)
end sub

sub toggleFavorite()
    if m.currentChannel = invalid then return
    userInfo = m.global.session
    if not tvHasSession(userInfo) then return

    accion = tvToggleFavoriteAction(m.favoriteIds, m.currentChannel.cnId)
    if accion = "add"
        url = tvApiAddFavoriteUrl(m.brand.baseUrl, userInfo.userEmail, m.currentChannel.cnId)
    else
        url = tvApiDeleteFavoriteUrl(m.brand.baseUrl, userInfo.userEmail, m.currentChannel.cnId)
    end if
    print "[TV] favorito "; accion; " cn="; m.currentChannel.cnId

    ' Actualización optimista: la estrella responde al instante. La lista de verdad la sigue
    ' mandando get-favorite en la recarga de después.
    m.favoriteIds = tvToggleFavoriteLocal(m.favoriteIds, m.currentChannel.cnId)
    m.global.favoriteIds = m.favoriteIds
    refreshFavoriteState()

    m.toggleTask = CreateObject("roSGNode", "ApiTask")
    m.toggleTask.observeField("response", "onToggleFavoriteResponse")
    m.toggleTask.request = tvApiRequest(url)
    m.toggleTask.control = "RUN"
end sub

sub onToggleFavoriteResponse()
    ' El servidor es la fuente de verdad: se recarga en vez de fiarse del optimismo.
    fetchFavorites()
end sub

sub refreshGrid()
    now& = tvNowSeconds()
    m.epgWindow = tvBuildEpgWindow(m.guide, m.filtered, now&, m.brand.isCatchupClient, m.catchupVerified, m.utcOffset)

    ' El ORDEN importa: asignar `channels` dispara la reconstruccion de la parrilla, que enfoca la
    ' fila del canal en emision. Si `currentCnId` se pone despues, la parrilla se enfoca con el
    ' valor VIEJO y el marco se queda en el canal anterior. Visto en el simulador el 2026-09-21.
    if m.currentChannel <> invalid then m.grid.currentCnId = m.currentChannel.cnId
    m.grid.epgWindow = m.epgWindow
    m.grid.channels = m.filtered
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

    m.top.currentCnId = m.currentChannel.cnId
    m.global.currentCnId = m.currentChannel.cnId
    refreshInfo()
    refreshFavoriteState()
end sub

' Vuelta de pantalla completa: el usuario puede haber zapeado. Se actualiza la info y la parrilla
' SIN volver a arrancar el vídeo, que ya está sonando con ese canal.
sub onSyncChannel()
    channel = tvFindChannelByCnId(m.channels, m.top.syncCnId)
    if channel = invalid then return
    m.currentChannel = channel
    m.top.currentCnId = channel.cnId
    refreshInfo()
    refreshGrid()
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

    ' Orden verificado contra el original (player.js:160-169): premium ANTES que adulto, y la
    ' restriccion por IP la ultima porque es la unica que gasta una llamada de red.
    paso = tvResolveLaunchStep(channel, m.sections, premiumsActuales(), m.adultUnlocked)

    if paso <> "play" and paso <> "ip"
        m.top.blockedReason = paso
        return
    end if

    if paso = "ip"
        validateIpAndPlay(channel)
        return
    end if

    ' TODO(CU-14/15): aquí va el paso por tvResolveLaunchStep (premium → adulto → IP). El PIN
    ' parental está bloqueado hasta resolver lo de bcrypt (plan_migracion.md §8.1).
    m.currentChannel = channel
    playCurrent()
    refreshGrid()
end sub

sub onDisplayAction()
    if m.display.action = "fullscreen" then m.top.requestFullscreen = true
    if m.display.action = "mylist" then toggleFavorite()
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

