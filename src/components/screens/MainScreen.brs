' Contenedor post-login. Ver MainScreen.xml.
'
' ⚠ Toca el dispositivo: no se ejecuta en `npm test`.

sub init()
    print "[TV] MainScreen.init"
    m.brand = m.global.brand

    m.live = m.top.findNode("live")
    m.navBar = m.top.findNode("navBar")
    m.navBar.observeField("action", "onNavAction")

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
end sub

sub onVideoNodeChanged()
    m.live.videoNode = m.top.videoNode
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
        ' El menú de perfil (Perfil / Mi Plan / Cambiar contraseña / Cerrar sesión) llega con su
        ' pantalla. Por ahora es la salida, para poder probar el ciclo completo en el aparato.
        m.top.logout = true
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
