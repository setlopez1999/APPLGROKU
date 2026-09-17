' Contenedor post-login. Ver MainScreen.xml.
'
' ⚠ Toca el dispositivo: no se ejecuta en `npm test`.

sub init()
    m.brand = m.global.brand

    m.top.findNode("bg").color = m.brand.background

    m.greeting = m.top.findNode("greeting")
    m.summary = m.top.findNode("summary")
    m.hint = m.top.findNode("hint")

    m.greeting.color = m.brand.textPrimary
    m.summary.color = m.brand.textSecondary
    m.hint.color = m.brand.textDisabled

    m.navBar = m.top.findNode("navBar")
    m.navBar.observeField("action", "onNavAction")

    ' Las pestañas se resuelven con la regla probada: switch de marca × lo que manda el backend.
    userInfo = m.global.session
    m.navBar.tabs = tvResolveTabs(m.brand, "absent", tvContentAvailabilityFromUserInfo(userInfo))
    m.navBar.selectedTab = tvStartTab()
    m.navBar.barFocused = true
    m.navBar.setFocus(true)

    renderSummary(userInfo)
end sub

' Resumen de la sesión: sirve para confirmar en el aparato que el login llega con datos de verdad.
' Lo reemplaza LiveScreen.
sub renderSummary(userInfo as object)
    if userInfo = invalid
        m.greeting.text = "Sesión no disponible"
        return
    end if

    channels = m.global.channels
    sections = m.global.sections
    total = 0
    if channels <> invalid then total = channels.Count()
    categorias = 0
    if sections <> invalid then categorias = sections.Count()

    m.greeting.text = "Hola, " + userInfo.user
    m.summary.text = Str(total).Trim() + " canales reproducibles en " + Str(categorias).Trim() + " categorías  ·  plan " + userInfo.plan
    m.hint.text = "Siguiente: TV en directo (preview + categorías + parrilla)"
end sub

sub onNavAction()
    action = m.navBar.action

    if action = "profile"
        ' El menú de perfil (Perfil / Mi Plan / Cambiar contraseña / Cerrar sesión) llega con su
        ' pantalla. Por ahora sirve de salida para poder probar el ciclo completo en el aparato.
        m.top.logout = true
        return
    end if

    if action = "home" or action = "live" or action = "events" or action = "content"
        m.navBar.selectedTab = action
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    ' Con una sola pantalla el foco vive en la barra. Cuando exista LiveScreen, abajo se baja al
    ' contenido y arriba se vuelve a la barra.
    if key = "down" or key = "up" then return true

    return false
end function
