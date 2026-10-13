' Contenedor post-login. Ver MainScreen.xml.
'
' ⚠ Toca el dispositivo: no se ejecuta en `npm test`.

sub init()
    print "[TV] MainScreen.init"
    m.brand = m.global.brand

    m.live = m.top.findNode("live")
    m.navBar = m.top.findNode("navBar")
    m.navBar.observeField("action", "onNavAction")
    m.live.observeField("blockedReason", "onBlockedReason")
    ' CU-12/CU-24: la barra superior se oculta CON el overlay. No tiene sentido dejarla flotando
    ' sobre el video limpio.
    m.live.observeField("overlayVisible", "onOverlayVisible")
    m.live.observeField("requestCatchup", "onRequestCatchup")
    m.profileMenu = m.top.findNode("profileMenu")
    m.profileMenu.observeField("action", "onProfileAction")

    m.myList = m.top.findNode("myList")
    m.myList.observeField("chosenCnId", "onListChosen")
    m.search = m.top.findNode("search")
    m.search.observeField("chosenCnId", "onSearchChosen")

    ' Las pestañas se resuelven con la regla probada: switch de marca × lo que manda el backend.
    userInfo = m.global.session
    m.navBar.tabs = tvResolveTabs(m.brand, "absent", tvContentAvailabilityFromUserInfo(userInfo))
    m.navBar.selectedTab = tvStartTab()

    ' Dos zonas: la barra de arriba y el contenido. El foco arranca en el contenido, que es donde
    ' está lo que el usuario quiere hacer; la barra se alcanza subiendo.
    m.ZONE_NAV = 0
    m.ZONE_CONTENT = 1
    m.zone = m.ZONE_CONTENT
    applyZone()

    ' Un Group que recibe el foco SE LO QUEDA: hay que delegarlo a mano en el hijo activo. Sin
    ' esto, MainScene daba el foco a esta pantalla y las teclas no llegaban nunca a LiveScreen.
    ' Verificado en el simulador el 2026-09-21 (docs/ROKU-GOTCHAS.md §21).
    m.top.observeField("focusedChild", "onFocusReceived")
end sub

' Mismo criterio que LiveScreen: si el foco sale de esta pantalla (un modal de la escena), la barra
' superior deja de verse enfocada. Dos resaltados a la vez dejan al usuario sin saber qué responde.
sub onFocusReceived()
    if m.top.isInFocusChain()
        applyZone()
        return
    end if
    m.navBar.barFocused = false
end sub

sub onVideoNodeChanged()
    m.live.videoNode = m.top.videoNode
end sub

' CU-12 — La barra superior vive y muere con el overlay.
'
' Y el foco NO puede quedarse en ella al ocultarse: si se queda en un nodo invisible, el mando
' deja de responder. Por eso al ocultar el overlay el foco baja al contenido, que es quien tiene
' el receptor de teclas de pantalla completa.
sub onOverlayVisible()
    visible = m.live.overlayVisible
    m.navBar.visible = visible

    if not visible and m.zone = m.ZONE_NAV
        m.zone = m.ZONE_CONTENT
        applyZone()
    end if
end sub

' Mi lista y Buscar son pantallas que se superponen a la pestana, no pestanas nuevas: asi el
' ATRAS devuelve a donde estabas, que es lo que espera el usuario.
sub openTopScreen(pantalla as object)
    m.myList.visible = false
    m.search.visible = false

    ' Los datos salen del estado global; estas pantallas no piden nada por su cuenta.
    canales = m.global.channels
    if canales = invalid then canales = []

    if pantalla.id = "myList"
        pantalla.currentCnId = m.live.currentCnId
        pantalla.epgWindow = m.live.epgWindow
        pantalla.channels = tvFavoriteChannels(m.global.favoriteIds, canales)
    else
        pantalla.epgWindow = m.live.epgWindow
        pantalla.channels = canales
    end if

    pantalla.visible = true
    pantalla.setFocus(true)
end sub

sub closeTopScreen()
    m.myList.visible = false
    m.search.visible = false
    applyZone()
end sub

sub onListChosen()
    closeTopScreen()
    m.live.syncCnId = m.myList.chosenCnId
    m.live.playCnId = m.myList.chosenCnId
end sub

sub onSearchChosen()
    closeTopScreen()
    m.live.syncCnId = m.search.chosenCnId
    m.live.playCnId = m.search.chosenCnId
end sub

sub openProfileMenu()
    m.profileMenu.visible = true
    m.profileMenu.setFocus(true)
end sub

sub closeProfileMenu()
    m.profileMenu.visible = false
    applyZone()
end sub

sub onProfileAction()
    if m.profileMenu.action = "logout"
        m.top.logout = true
        return
    end if
    closeProfileMenu()
end sub

sub onAdultUnlocked()
    m.live.adultUnlocked = m.top.adultUnlocked
end sub

sub onRequestCatchup()
    m.top.catchupTarget = m.live.requestCatchup
end sub

sub onBlockedReason()
    m.top.blockedReason = m.live.blockedReason
end sub

sub onCatalogVersion()
    m.live.catalogVersion = m.top.catalogVersion
end sub

sub onResumeLive()
    m.live.resumeLive = m.top.resumeLive
end sub

' ---- certificacion 5.1/5.2: enlaces profundos --------------------------------

sub onStartCnId()
    m.live.startCnId = m.top.startCnId
end sub

' Enlace profundo con la app YA ABIERTA. Entra por el MISMO camino que Buscar y Mi lista
' (`playCnId` -> `tuneWithAccessChecks`), que es el unico que pasa por los controles de acceso: un
' enlace no puede ser el atajo que se salta el pack premium o el PIN de adultos.
sub onDeepLinkCnId()
    cnId = m.top.deepLinkCnId
    if cnId <= 0 then return

    ' Un enlace profundo lleva AL CONTENIDO: si habia una pantalla superpuesta o el menu de cuenta
    ' abiertos, el usuario acabaria mirando el canal correcto a traves de un panel que el no abrio.
    m.profileMenu.visible = false
    closeTopScreen()

    m.live.playCnId = cnId
end sub

sub onCatchupAnchor()
    m.live.catchupAnchorCnId = m.top.catchupAnchorCnId
    m.zone = m.ZONE_CONTENT
    applyZone()
end sub

sub applyZone()
    m.navBar.barFocused = (m.zone = m.ZONE_NAV)
    if m.zone = m.ZONE_NAV
        m.navBar.setFocus(true)
    else
        m.live.setFocus(true)
    end if
end sub

sub onNavAction()
    action = m.navBar.action

    if action = "profile"
        openProfileMenu()
        return
    end if

    if action = "mylist"
        openTopScreen(m.myList)
        return
    end if

    if action = "search"
        openTopScreen(m.search)
        return
    end if

    if action = "home" or action = "live" or action = "events" or action = "content"
        m.navBar.selectedTab = action
        ' Solo "TV en directo" tiene pantalla; el resto quedan como pestañas sin contenido hasta que
        ' se construyan.
        m.zone = m.ZONE_CONTENT
        applyZone()
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    ' El menú de cuenta tiene prioridad: mientras está abierto, el resto de la pantalla no responde
    ' (prioridad del ATRÁS, docs/plan_migracion.md §6).
    if m.profileMenu.visible then return false

    if m.myList.visible or m.search.visible
        if key = "back"
            closeTopScreen()
            return true
        end if
        return false
    end if

    ' Con el overlay oculto la barra NO está dibujada, así que no se puede subir a ella: el foco
    ' acabaría en un nodo invisible y el mando dejaría de responder. (En la práctica LiveScreen ya
    ' se queda las flechas para zapear, pero el guard no sobra: es el fallo más caro de la app.)
    if not m.live.overlayVisible then return false

    ' LiveScreen deja pasar el "arriba" cuando ya está en su zona más alta: ahí se sube a la barra.
    if key = "up" and m.zone = m.ZONE_CONTENT
        m.zone = m.ZONE_NAV
        applyZone()
        return true
    end if

    if key = "down" and m.zone = m.ZONE_NAV
        m.zone = m.ZONE_CONTENT
        applyZone()
        return true
    end if

    return false
end function
