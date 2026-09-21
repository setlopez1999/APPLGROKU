' Contenedor post-login. Ver MainScreen.xml.
'
' ⚠ Toca el dispositivo: no se ejecuta en `npm test`.

sub init()
    print "[TV] MainScreen.init"
    m.brand = m.global.brand

    m.live = m.top.findNode("live")
    m.navBar = m.top.findNode("navBar")
    m.navBar.observeField("action", "onNavAction")
    m.live.observeField("requestFullscreen", "onRequestFullscreen")
    m.profileMenu = m.top.findNode("profileMenu")
    m.profileMenu.observeField("action", "onProfileAction")

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

sub onFocusReceived()
    if m.top.hasFocus() then applyZone()
end sub

sub onVideoNodeChanged()
    m.live.videoNode = m.top.videoNode
end sub

' La pila de pantallas la gobierna MainScene: aquí solo se reenvía la petición hacia arriba.
sub onRequestFullscreen()
    m.top.fullscreenCnId = m.live.currentCnId
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

sub onCatalogVersion()
    m.live.catalogVersion = m.top.catalogVersion
end sub

sub onResume()
    m.live.syncCnId = m.top.resumeCnId
    m.live.setFocus(true)
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
