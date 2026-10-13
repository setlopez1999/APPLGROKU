' "TV en directo" — LA pantalla de la app, con sus dos modos. Ver LiveScreen.xml.
'
' ⚠ Toca el dispositivo: no se ejecuta en `npm test`. Toda la lógica que DECIDE algo (categorías,
' primer canal, ventana del EPG, info del canal, zapping, prioridad del ATRÁS, cuándo recargar el
' reproductor) está en `domain/` y sí tiene tests; aquí solo hay composición, foco y reproductor.

sub init()
    print "[TV] LiveScreen.init"
    m.brand = m.global.brand

    m.overlay = m.top.findNode("overlay")
    m.display = m.top.findNode("display")
    m.tabs = m.top.findNode("tabs")
    m.grid = m.top.findNode("grid")
    m.strip = m.top.findNode("strip")
    m.keyCatcher = m.top.findNode("keyCatcher")

    m.status = m.top.findNode("status")
    m.status.color = m.brand.textSecondary
    m.loading = m.top.findNode("loadingBox")
    m.top.findNode("loadingBg").color = m.brand.surface
    m.top.findNode("loading").color = m.brand.textPrimary

    m.top.findNode("gridBackground").color = m.brand.background

    buildFades()

    m.display.observeField("action", "onDisplayAction")
    m.tabs.observeField("chosenIndex", "onCategoryChosen")
    m.grid.observeField("chosenCnId", "onChannelChosen")
    m.grid.observeField("chosenCatchup", "onCatchupChosen")

    ' Zonas de foco. El foco NUNCA se queda atrapado en una: cada componente deja pasar
    ' arriba/abajo y aquí se decide a dónde va (arquitectura_flujo.md §5).
    ' "keys" es la zona del modo pantalla completa, con el overlay oculto.
    m.zone = "grid"

    m.channels = []
    m.filtered = []
    m.sections = []
    m.currentChannel = invalid
    m.guide = {}
    m.epgWindow = { cells: {}, pastColumns: 0, futureColumns: 0 }
    m.catchupVerified = []
    m.favoriteIds = []
    m.favoritesBeforeToggle = []
    m.pendingAdultChannel = invalid
    m.deviceIp = ""
    m.pendingChannel = invalid
    m.utcOffset = tvDeviceUtcOffsetSec()

    ' Certificación 5.1 — enlace profundo del arranque en frío. `directo` es el caso bueno: el
    ' canal pedido ya es el inicial y solo falta dejar el vídeo limpio. `bloqueado` es el canal
    ' pedido que necesita pack, PIN o validación de IP, y se resuelve al acabar el arranque por el
    ' camino de siempre, que es el único que sabe pedirlos.
    m.deepLinkDirect = false
    m.deepLinkBlocked = invalid

    ' La url que está REALMENTE cargada en el reproductor. Es lo que permite no recargar cuando no
    ' hace falta: sin esto cada redibujado reinicia el vídeo y la imagen parpadea (CU-09).
    m.loadedUrl = ""
    m.retryAttempts = 0

    m.autoHideTimer = m.top.findNode("autoHideTimer")
    m.autoHideTimer.observeField("fire", "onAutoHide")
    m.stripTimer = m.top.findNode("stripTimer")
    m.stripTimer.observeField("fire", "onStripTimer")
    m.retryTimer = m.top.findNode("retryTimer")
    m.retryTimer.observeField("fire", "onRetryTimer")
    m.loadingTimer = m.top.findNode("loadingTimer")
    m.loadingTimer.observeField("fire", "onLoadingTimer")
    m.stallTimer = m.top.findNode("stallTimer")
    m.stallTimer.observeField("fire", "onStallTick")
    m.secondsOutOfPlaying = 0
    m.lastBufferPct = -1

    ' El primer dibujado NO mueve el foco: nadie ha alternado nada todavía.
    applyOverlayMode(true, false)

    ' El trabajo pesado NO se hace aquí: se reparte en pasos, uno por tick (ver bootTimer).
    m.bootStep = 0
    m.bootTimer = m.top.findNode("bootTimer")
    m.bootTimer.observeField("fire", "onBootStep")
    m.bootTimer.control = "start"

    ' Igual que MainScreen: si esta pantalla recibe el foco, lo delega en su zona activa
    ' (docs/ROKU-GOTCHAS.md §21).
    m.top.observeField("focusedChild", "onFocusReceived")
end sub

' Cuando el foco SALE de esta pantalla (sube a la barra superior, se abre un modal o una pantalla
' apilada), hay que APAGAR el resaltado de la zona. Si no, el botón o la píldora que tenía el foco
' se queda iluminado y en pantalla parecen dos cosas enfocadas a la vez: el usuario no sabe cuál
' responde al OK. Visto en el Roku Express el 2026-10-12 al subir del display a la barra.
'
' `isInFocusChain()` y no `hasFocus()`: el foco real lo tiene un hijo (la parrilla, las píldoras),
' así que `hasFocus()` es false casi siempre y apagaría el resaltado constantemente.
sub onFocusReceived()
    if m.top.isInFocusChain()
        applyZone()
        return
    end if
    clearZoneHighlight()
end sub

sub clearZoneHighlight()
    m.display.barFocused = false
    m.tabs.barFocused = false
    m.grid.gridFocused = false
end sub

' Los degradados son PNG generados en el build, no rectángulos apilados.
'
' El apilado con alfa escalonada era la solución anterior —SceneGraph no tiene degradados— y en el
' Roku Express SE VEÍA A BANDAS: con 18 escalones, cada salto de opacidad se distingue sobre el
' vídeo y la pantalla parece hecha a bloques. Con un PNG de una fila por píxel el salto es de
' 1/255 y desaparece. Verificado en el aparato el 2026-10-12.
'
' El velo del header no baja de 0.35 (el Kotlin lo apaga del todo a los 420 px): aquí el texto del
' canal quedaba sobre vídeo crudo y, con una imagen clara detrás, no se leía.
sub buildFades()
    m.top.findNode("leftFade").uri = "pkg:/images/fade_left.png"
    m.top.findNode("headerFade").uri = "pkg:/images/fade_header.png"
    m.top.findNode("epgFade").uri = "pkg:/images/fade_epg.png"
end sub

' ---- CU-12: los dos modos ----------------------------------------------------
'
' No son dos pantallas: es la misma con una capa que aparece y desaparece. Por eso el vídeo no se
' corta al alternar — nadie toca el reproductor aquí.

sub applyOverlayMode(visible as boolean, moveFocus as boolean)
    m.top.overlayVisible = visible
    m.overlay.visible = visible

    if visible
        ' La franja es del modo pantalla completa: con la guía abierta ya está la info arriba.
        hideStrip()
        ' La cuenta de los 2 minutos SOLO corre con el overlay visible: con el overlay oculto no
        ' hay nada que ocultar.
        restartAutoHide()
    else
        m.autoHideTimer.control = "stop"
    end if

    ' Al alternar hay que mover el foco EXPLÍCITAMENTE, o se queda en un nodo que ya no se dibuja
    ' y el mando deja de responder. Se salta en el primer dibujado, cuando nadie ha alternado nada.
    if not moveFocus then return

    if tvOverlayFocusTarget(visible) = "tabs"
        m.zone = "tabs"
    else
        m.zone = "keys"
    end if
    applyZone()
end sub

sub showOverlay()
    if m.top.overlayVisible then return
    applyOverlayMode(true, true)
end sub

sub hideOverlay()
    if not m.top.overlayVisible then return
    applyOverlayMode(false, true)
end sub

' CUALQUIER pulsación reinicia la cuenta, incluidas las que no hacen nada visible: lo que se mide
' es inactividad del usuario, no cambios de estado.
sub restartAutoHide()
    m.autoHideTimer.control = "stop"
    m.autoHideTimer.control = "start"
end sub

' Equivale a un ATRÁS automático. El caso habitual en un televisor es que el usuario abra la guía,
' elija un canal y se vaya o se duerma; sin esto el aparato se queda horas con la guía encima.
sub onAutoHide()
    video = m.top.videoNode
    estado = ""
    if video <> invalid then estado = video.state

    ' Si no hay vídeo en marcha, no hay nada que destapar: ocultar la guía dejaría un negro mudo.
    ' La cuenta se reinicia y se vuelve a intentar dentro de 2 minutos.
    if not tvCanAutoHideOverlay(estado)
        print "[TV] overlay: 2 min sin actividad, pero el vídeo está en '"; estado; "' — no se oculta"
        restartAutoHide()
        return
    end if

    print "[TV] overlay: 2 min sin actividad, se oculta"
    hideOverlay()
end sub

' ---- CU-13: la franja del canal ----------------------------------------------

sub showStrip()
    if m.currentChannel = invalid then return

    programs = tvProgramsForChannel(m.guide, m.currentChannel.cnId)
    m.strip.info = tvBuildChannelInfo(m.currentChannel, programs, tvNowSeconds(), m.utcOffset)
    m.strip.visible = true

    ' Se reinicia en cada zap: si no, la franja se esconde mientras el usuario sigue cambiando.
    m.stripTimer.control = "stop"
    m.stripTimer.control = "start"
end sub

sub hideStrip()
    m.strip.visible = false
    m.stripTimer.control = "stop"
end sub

sub onStripTimer()
    m.strip.visible = false
end sub

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

    m.currentChannel = pickInitialChannel()
    if m.currentChannel <> invalid
        print "[TV] canal inicial: "; m.currentChannel.nombre; " ("; m.currentChannel.numero; ")"
    else
        print "[TV] NINGUN canal reproducible"
        m.status.text = "No hay canales disponibles"
    end if
end sub

' El canal con el que arranca la pantalla.
'
' Normalmente es el primero permitido (CU-05). Pero si la app se abrió con un ENLACE PROFUNDO, el
' canal pedido tiene que ser EL PRIMERO que se sintoniza, no uno al que se salta después: arrancar
' el primero y cambiar acto seguido son dos streams para una sola pulsación, y Roku cronometra el
' tiempo hasta el primer fotograma (criterio 3.6, 8 s).
'
' Los controles de acceso NO se saltan, que es el riesgo entero de un enlace profundo: si el canal
' pedido es de pago, de adultos o está restringido por IP, se arranca con el primero permitido y el
' enlace se resuelve al final del arranque por `tuneWithAccessChecks`, que es el único camino que
' sabe abrir el aviso de venta, pedir el PIN o consultar la IP.
'
' Que el canal exista ya lo comprobó MainScene contra el catálogo; la comprobación de aquí es por
' si el catálogo cambió entre medias.
function pickInitialChannel() as object
    primero = tvGetFirstAllowedChannel(m.channels, m.sections, premiumsActuales())
    if m.top.startCnId <= 0 then return primero

    pedido = tvFindChannelByCnId(m.channels, m.top.startCnId)
    if pedido = invalid then return primero

    if tvResolveLaunchStep(pedido, m.sections, premiumsActuales(), m.global.adultUnlocked) = "play"
        m.deepLinkDirect = true
        return pedido
    end if

    print "[TV] enlace profundo: el canal pedido necesita permisos, se resuelve al arrancar"
    m.deepLinkBlocked = pedido
    return primero
end function

' Se llama al terminar el arranque, con la parrilla ya montada.
'
' Un enlace profundo entra EN EL CONTENIDO, no en la guía: eso es lo que significa el requisito
' "launch directly into the content". Así que se deja el vídeo limpio, y la franja de 5 s dice a
' qué canal se ha llegado (CU-13) — sin ella el usuario no sabría si el enlace funcionó.
sub finishDeepLink()
    if m.deepLinkDirect
        m.deepLinkDirect = false
        hideOverlay()
        showStrip()
        return
    end if

    if m.deepLinkBlocked = invalid then return

    pedido = m.deepLinkBlocked
    m.deepLinkBlocked = invalid

    ' Si sale el aviso de venta o el PIN, el overlay se queda: ocultarlo dejaría al usuario
    ' mirando un modal sobre un canal que no es el que pidió.
    if tuneWithAccessChecks(pedido) then hideOverlay()
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
    ' Se reintenta POR SU CUENTA, aunque el catálogo no haya cambiado: viene de otro endpoint y
    ' puede estar caída sola (CU-14). Mientras tanto la pantalla está DEGRADADA y la revalidación
    ' baja su ritmo de 60 s a 8 s para engancharla en cuanto vuelva.
    if tvEpgIsEmpty(m.guide)
        m.status.text = "Guía no disponible, reintentando…"
        m.global.guideDegraded = true
        return
    end if

    m.status.text = ""
    m.global.guideDegraded = false
    refreshGrid()
    refreshInfo()
    probeCatchup()
end sub

' El catálogo cambió de verdad (la revalidación ya lo ha comprobado). Se repintan categorías y
' parrilla, y se decide qué hacer con lo que está sonando SIN cortarlo si no hace falta.
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

    ' "reload" (la url cambió), "switch" (el canal ya no existe) o "blocked" (se perdió el premium)
    if decision.action = "blocked"
        m.status.text = "Este canal ya no está incluido en tu plan"
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

' ---- CU-15: catch-up ---------------------------------------------------------
'
' El flag del backend no basta: hay que SONDEAR (docs/BACKEND-GOTCHAS.md §3). Hasta que la sonda
' responda, ningún canal cuenta como reproducible y no se dibuja el play.

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
    ' Se reconstruye la ventana: ahora ya se sabe en qué celdas se puede dibujar el play.
    refreshGrid()
end sub

sub onCatchupChosen()
    destino = m.grid.chosenCatchup
    if destino = invalid then return
    if destino.url = "" then return
    m.top.requestCatchup = destino
end sub

' CU-10 — Al volver de una grabación, la parrilla vuelve a la fila del canal DE LA GRABACIÓN, no a
' la del canal que sigue sonando, y el foco regresa a la grilla.
'
' Sin lo primero el usuario aparece en otro punto de la lista y pierde el sitio. Sin lo segundo el
' foco se queda en el aire y el mando deja de responder.
sub onCatchupAnchor()
    cnId = m.top.catchupAnchorCnId
    if cnId <= 0 then return

    ' El ancla es de UNA SOLA VEZ y se consume aquí. Si viviera en el estado permanente, el foco
    ' volvería a la grilla en cada redibujado y el usuario no podría moverse a ningún otro sitio.
    m.top.catchupAnchorCnId = 0

    applyOverlayMode(true, false)
    m.grid.anchorCnId = cnId
    m.zone = "grid"
    applyZone()
end sub

' CU-15 — Volver del reproductor de grabaciones. El directo se DETUVO para liberar el decodificador,
' así que hay que volver a PREPARARLO: un "reanudar" no hace nada sobre un reproductor detenido y
' el canal se quedaría negro.
sub onResumeLive()
    if not m.top.resumeLive then return
    m.loadedUrl = ""
    playCurrent()
end sub

' Vuelta del PIN correcto: se reproduce el canal que se había intentado abrir.
sub onAdultUnlocked()
    if not m.top.adultUnlocked then return
    canal = m.pendingAdultChannel
    m.pendingAdultChannel = invalid
    if canal = invalid then return

    m.currentChannel = canal
    playCurrent()
    refreshGrid()
end sub

' ---- CU-20: restricción por IP -----------------------------------------------
'
' Solo para los canales con `restriccion = 1`. Es la última validación porque es la única que gasta
' llamadas de red. El body real es {ip, cn_id}, con el cn_id COMO TEXTO.

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

    ' Ante cualquier duda, DENEGAR: es un control de derechos de emisión, y el error seguro es el
    ' que deniega (CU-20).
    if not m.ipTask.response.ok or m.ipTask.response.statusCode = 403
        m.top.blockedReason = "ip"
        return
    end if

    m.currentChannel = canal
    playCurrent()
    refreshGrid()
end sub

' ---- CU-16: favoritos --------------------------------------------------------

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
    ' Un fallo conserva la lista anterior: no se vacía la pantalla por un hipo de red.
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

    ' Cambio inmediato, confirmación después: esperar la respuesta del servidor antes de mover el
    ' icono se percibe como que el botón no funciona (CU-16).
    m.favoritesBeforeToggle = m.favoriteIds
    m.favoriteIds = tvToggleFavoriteLocal(m.favoriteIds, m.currentChannel.cnId)
    m.global.favoriteIds = m.favoriteIds
    refreshFavoriteState()

    m.toggleTask = CreateObject("roSGNode", "ApiTask")
    m.toggleTask.observeField("response", "onToggleFavoriteResponse")
    m.toggleTask.request = tvApiRequest(url)
    m.toggleTask.control = "RUN"
end sub

sub onToggleFavoriteResponse()
    ' Si el servidor dijo que no, SE REVIERTE y el icono vuelve a su estado anterior (CU-16). Sin
    ' esto queda marcado algo que el servidor no tiene, y el usuario no se entera.
    if not m.toggleTask.response.ok
        print "[TV] favorito: el servidor fallo, se revierte"
        m.favoriteIds = m.favoritesBeforeToggle
        m.global.favoriteIds = m.favoriteIds
        refreshFavoriteState()
        return
    end if

    ' Tras cada cambio se vuelve a pedir la lista completa: es la forma de concordar con el
    ' servidor cuando la misma cuenta se usa en varios equipos a la vez.
    fetchFavorites()
end sub

sub refreshGrid()
    now& = tvNowSeconds()
    m.epgWindow = tvBuildEpgWindow(m.guide, m.filtered, now&, m.brand.isCatchupClient, m.catchupVerified, m.utcOffset)

    ' El ORDEN importa: asignar `channels` dispara la reconstrucción de la parrilla, que enfoca la
    ' fila del canal en emisión. Si `currentCnId` se pone después, la parrilla se enfoca con el
    ' valor VIEJO y el marco se queda en el canal anterior. Visto en el simulador el 2026-09-21.
    if m.currentChannel <> invalid then m.grid.currentCnId = m.currentChannel.cnId
    m.grid.epgWindow = m.epgWindow
    m.grid.channels = m.filtered
    m.top.epgWindow = m.epgWindow
end sub

sub refreshInfo()
    if m.currentChannel = invalid then return
    programs = tvProgramsForChannel(m.guide, m.currentChannel.cnId)
    m.display.info = tvBuildChannelInfo(m.currentChannel, programs, tvNowSeconds(), m.utcOffset)
end sub

' ---- reproducción ------------------------------------------------------------

sub onVideoNodeReady()
    video = m.top.videoNode
    if video = invalid then return

    ' CU-09: sin observar el estado, un stream caído deja la pantalla NEGRA sin mensaje, sin
    ' reintento y sin que el usuario sepa si se colgó la app o el canal no existe.
    '
    ' `observeFieldScoped` y no `observeField`: el nodo Video es compartido y vive más que esta
    ' pantalla, así que un observador sin ámbito seguiría vivo después de destruirla.
    video.observeFieldScoped("state", "onVideoState")
    m.videoListo = true
end sub

' Un paso por tick. Ninguno es lo bastante gordo para agotar el presupuesto del frame.
sub onBootStep()
    m.bootStep = m.bootStep + 1

    if m.bootStep = 1
        loadCatalog()
        return
    end if

    if m.bootStep = 2
        playCurrent()
        return
    end if

    if m.bootStep = 3
        refreshGrid()
        return
    end if

    if m.bootStep = 4
        fetchGuide()
        fetchFavorites()
        m.bootTimer.control = "stop"

        ' Al final del arranque y no antes: `hideOverlay` mueve el foco, y hacerlo con la parrilla
        ' a medio construir lo deja en un nodo que todavía no está dibujado.
        finishDeepLink()
    end if
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

    m.status.text = ""

    ' CU-09, regla de carga: solo se recarga si la url cambió. Sin esto cada redibujado provoca una
    ' recarga y el vídeo parpadea constantemente.
    if tvResolveStreamLoad(m.loadedUrl, m.currentChannel.streamUrl, video.state) = "none"
        syncCurrentChannelState()
        return
    end if

    content = CreateObject("roSGNode", "ContentNode")
    content.url = m.currentChannel.streamUrl
    content.streamformat = "hls"
    content.title = m.currentChannel.nombre
    applyStreamHeaders(content)

    ' DETENER, no pausar: pausar NO libera el decodificador, y solo hay uno (§9). Vale tanto para
    ' cambiar de canal como para volver a preparar tras una detención.
    video.control = "stop"
    video.content = content
    video.control = "play"
    video.visible = true

    m.loadedUrl = m.currentChannel.streamUrl
    m.retryAttempts = 0
    m.secondsOutOfPlaying = 0
    m.stallTimer.control = "start"
    syncCurrentChannelState()
end sub

sub syncCurrentChannelState()
    if m.currentChannel = invalid then return
    m.top.currentCnId = m.currentChannel.cnId
    m.global.currentCnId = m.currentChannel.cnId
    refreshInfo()
    refreshFavoriteState()
end sub

' CU-09 — En HLS en vivo los cortes son NORMALES: la ventana de emisión se queda atrás, el servidor
' rota, hay un hipo de red. La respuesta correcta es siempre la misma y NO tiene tope: con tope, al
' agotarlo el canal se queda negro para siempre y hay que reiniciar el canal entero.
sub onVideoState()
    video = m.top.videoNode
    if video = invalid then return


    ' El reproductor es compartido: mientras hay una grabación encima, su estado no es asunto de
    ' esta pantalla. Sin este guard los dos reintentos pelearían por el mismo nodo Video.
    if m.global.catchupActive then return

    estado = video.state

    if estado = "error"
        m.loadingTimer.control = "stop"
        m.loading.visible = false

        url = ""
        if m.currentChannel <> invalid then url = m.currentChannel.streamUrl
        if not tvShouldRetryPlayback(url, m.retryAttempts) then return

        m.retryAttempts = m.retryAttempts + 1
        print "[TV] reproduccion: error, reintento "; m.retryAttempts; " en 2 s"
        m.status.text = "Reconectando…"
        m.retryTimer.control = "stop"
        m.retryTimer.control = "start"
        return
    end if

    if estado = "playing"
        m.loadingTimer.control = "stop"
        m.loading.visible = false
        m.status.text = ""
        m.retryAttempts = 0
        return
    end if

    if estado = "buffering"
        ' Certificación 3.4 de Roku: indicador obligatorio si tarda más de 3 s. Antes de eso no se
        ' dibuja nada: un indicador que parpadea en cada cambio de canal se ve peor que ninguno.
        m.loadingTimer.control = "stop"
        m.loadingTimer.control = "start"
    end if
end sub

' CU-09 — El perro guardián del atasco mudo.
'
' El reintento por `error` no basta: el fallo más común de HLS en vivo no reporta error ninguno,
' el canal simplemente se queda en `buffering` y ahí muere. Esto cuenta cuánto lleva el
' reproductor FUERA de `playing` y, pasado el umbral, fuerza una recarga.
sub onStallTick()
    ' Mientras hay una grabación encima, el reproductor no es nuestro.
    if m.global.catchupActive then return

    video = m.top.videoNode
    if video = invalid then return
    if m.currentChannel = invalid then return
    if not tvIsPlayable(m.currentChannel) then return

    if video.state = "playing"
        m.secondsOutOfPlaying = 0
        m.lastBufferPct = -1
        return
    end if

    ' El bufer AVANZA = el reproductor está trabajando y llegará solo. Recargar ahí tira a la basura
    ' todo lo descargado y alarga el corte, que es exactamente lo que hacía la primera versión de
    ' esto: 19 recargas en 5 minutos sobre un canal que se recuperaba solo (medido el 2026-10-13).
    pct = bufferPercent(video)
    progresa = tvBufferIsProgressing(pct, m.lastBufferPct)
    m.lastBufferPct = pct

    if progresa
        m.secondsOutOfPlaying = 0
        return
    end if

    m.secondsOutOfPlaying = m.secondsOutOfPlaying + 1
    if not tvShouldRecoverFromStall(video.state, m.secondsOutOfPlaying, progresa) then return

    print "[TV] atasco: "; m.secondsOutOfPlaying; " s en '"; video.state; "' sin llenar bufer — se fuerza la recarga"
    m.secondsOutOfPlaying = 0
    m.lastBufferPct = -1
    m.status.text = "Reconectando…"
    m.loading.visible = true
    m.loadedUrl = ""
    playCurrent()
end sub

' Relleno del bufer en 0..100, o -1 si el reproductor no lo está reportando.
'
' `bufferingStatus` solo trae datos mientras hay relleno en curso; fuera de eso llega invalid, y
' por eso no vale comparar a ciegas.
function bufferPercent(video as object) as integer
    estado = video.bufferingStatus
    if estado = invalid then return -1
    if estado.percentage = invalid then return -1
    return Int(estado.percentage)
end function

sub onLoadingTimer()
    video = m.top.videoNode
    if video = invalid then return
    if video.state = "buffering" then m.loading.visible = true
end sub

sub onRetryTimer()
    if m.currentChannel = invalid then return

    ' Se fuerza la recarga: el reproductor está en error, no en un estado del que se pueda reanudar.
    m.loadedUrl = ""
    playCurrent()
end sub

' Lo piden Mi lista y Buscar al elegir un canal.
sub onPlayRequested()
    canal = tvFindChannelByCnId(m.channels, m.top.playCnId)
    if canal = invalid then return

    ' Mismo camino de controles de acceso que la guía y el zapping: no puede haber un atajo que se
    ' los salte, que es justo el fallo que deja ver un canal de pago desde una pantalla secundaria.
    '
    ' CU-12, tercera forma de ocultar el overlay: llegar desde otra pantalla con un canal pedido se
    ' deja el vídeo limpio. Pero SOLO si se llegó a sintonizar: si salió un aviso de premium o el
    ' PIN, ocultar la guía dejaría al usuario mirando un modal sobre un canal que no es el que pidió.
    if tuneWithAccessChecks(canal) then hideOverlay()
end sub

sub onSyncChannel()
    channel = tvFindChannelByCnId(m.channels, m.top.syncCnId)
    if channel = invalid then return
    m.currentChannel = channel
    m.top.currentCnId = channel.cnId
    refreshInfo()
    refreshGrid()
end sub

' El User-Agent del vídeo va en las CABECERAS DEL CONTENIDO, no con un roHttpAgent.
'
' VERIFICADO EN UN ROKU EXPRESS el 2026-09-21: crear `roHttpAgent` en el hilo de render dispara el
' watchdog y mata la reproducción antes de empezar:
'     Execution timeout (runtime error &h23) ... agent = CreateObject("roHttpAgent")
' El simulador lo aceptaba sin rechistar. Ver docs/ROKU-GOTCHAS.md §23.
'
' Sin este User-Agent, los servidores de Playcom devuelven 403 y el vídeo sale negro sin ningún
' error que lo explique (docs/BACKEND-GOTCHAS.md §1).
sub applyStreamHeaders(content as object)
    content.HttpHeaders = ["User-Agent: " + tvStreamUserAgent()]
end sub

' ---- CU-11: zapping ----------------------------------------------------------
'
' Solo con el overlay OCULTO. Con el overlay visible las flechas navegan la guía: si además
' cambiaran de canal, cada movimiento del foco cambiaría el canal.

sub zap(goingDown as boolean)
    actual = 0
    if m.currentChannel <> invalid then actual = m.currentChannel.cnId

    ' El recorrido es sobre la lista VISIBLE (la de la categoría elegida): si el usuario filtró por
    ' "Deportes", el zapping se queda en deportes. Es lo que espera, filtró para eso.
    siguiente = tvFindNextChannel(m.filtered, actual, goingDown, m.sections, premiumsActuales())

    ' invalid = ningún canal reproducible en toda la lista. Aquí el original entraba en recursión
    ' infinita y cerraba la app; se avisa y se deja el canal actual en marcha.
    if siguiente = invalid
        m.status.text = "No hay más canales disponibles"
        return
    end if

    sintonizo = tuneWithAccessChecks(siguiente)
end sub

' El ÚNICO camino para sintonizar. Venga de la guía, del zapping, del buscador o de Mi lista.
' Devuelve `true` solo si el canal se llegó a sintonizar.
function tuneWithAccessChecks(channel as object) as boolean
    ' Orden obligatorio: premium → adulto → IP. Premium primero porque pedirle el PIN a quien no
    ' tiene el pack contratado es absurdo: aunque acierte, seguirá sin poder verlo (CU-09).
    paso = tvResolveLaunchStep(channel, m.sections, premiumsActuales(), m.global.adultUnlocked)

    if paso <> "play" and paso <> "ip"
        ' Se guarda el canal: si el usuario acierta el PIN, se reproduce sin volver a elegirlo.
        if paso = "adult" then m.pendingAdultChannel = channel
        m.top.blockedReason = paso
        return false
    end if

    if paso = "ip"
        validateIpAndPlay(channel)
        return false
    end if

    m.currentChannel = channel
    playCurrent()
    refreshGrid()

    ' Con el overlay oculto, la franja es la única forma de saber a qué canal se ha llegado.
    if not m.top.overlayVisible then showStrip()
    return true
end function

' ---- interacción -------------------------------------------------------------

sub onCategoryChosen()
    index = m.tabs.chosenIndex
    m.tabs.selectedIndex = index

    if index = 0
        m.filtered = m.channels
    else
        m.filtered = tvChannelsForCategory(m.sections, index - 1)
    end if

    ' Cambiar de categoría NO cambia el canal que suena: son dos cosas independientes, el usuario
    ' explora mientras sigue viendo (CU-10).
    refreshGrid()
end sub

sub onChannelChosen()
    channel = tvFindChannelByCnId(m.channels, m.grid.chosenCnId)
    if channel = invalid then return
    sintonizo = tuneWithAccessChecks(channel)
end sub

sub onDisplayAction()
    if m.display.action = "mylist" then toggleFavorite()
end sub

' ---- foco --------------------------------------------------------------------

sub applyZone()
    m.display.barFocused = (m.zone = "display")
    m.tabs.barFocused = (m.zone = "tabs")
    m.grid.gridFocused = (m.zone = "grid")

    if m.zone = "display" then m.display.setFocus(true)
    if m.zone = "tabs" then m.tabs.setFocus(true)
    if m.zone = "grid" then m.grid.setFocus(true)
    if m.zone = "keys" then m.keyCatcher.setFocus(true)
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    ' CUALQUIER pulsación reinicia la cuenta del auto-ocultado, incluidas las que no hacen nada
    ' visible. Se OBSERVA sin consumirla: la tecla sigue su camino normal (CU-12).
    if m.top.overlayVisible then restartAutoHide()

    ' ---- modo pantalla completa (overlay oculto) ----
    if not m.top.overlayVisible
        if key = "OK"
            showOverlay()
            return true
        end if

        if tvShouldZap(m.top.overlayVisible)
            if key = "down"
                zap(true)
                return true
            end if
            if key = "up"
                zap(false)
                return true
            end if
        end if

        ' El ATRÁS NO se captura aquí: tiene que seguir su camino hasta la regla de salir de la
        ' app, con doble pulsación (CU-25). Si se consumiera, no habría forma de salir.
        return false
    end if

    ' ---- overlay visible ----
    if key = "back"
        ' Los niveles de más arriba (modales y pantallas apiladas) ni siquiera llegan hasta aquí:
        ' cuando están abiertos tienen el foco, así que resuelven su propio ATRÁS antes.
        accion = tvResolveBackAction(false, 1, true, m.zone)

        ' En la grilla, ATRÁS SUBE el foco y NO oculta la guía: el usuario que la está mirando
        ' quiere retroceder un paso, no perderla entera (CU-12).
        if accion = "focusTabs"
            m.zone = "tabs"
            applyZone()
            return true
        end if

        if accion = "hideOverlay"
            hideOverlay()
            return true
        end if

        return false
    end if

    if key = "down"
        if m.zone = "display"
            m.zone = "tabs"
            applyZone()
            return true
        end if
        if m.zone = "tabs"
            m.zone = "grid"
            applyZone()
            return true
        end if
        return false
    end if

    if key = "up"
        if m.zone = "grid"
            m.zone = "tabs"
            applyZone()
            return true
        end if
        if m.zone = "tabs"
            m.zone = "display"
            applyZone()
            return true
        end if
        ' Desde arriba del todo el foco sale hacia la barra superior: lo resuelve MainScreen.
        return false
    end if

    return false
end function
