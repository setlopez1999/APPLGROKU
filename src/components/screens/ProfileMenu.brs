' Menú de cuenta. Ver ProfileMenu.xml.
'
' ⚠ Toca el dispositivo: no se ejecuta en `npm test`.

sub init()
    m.brand = m.global.brand

    m.top.findNode("scrim").color = "0x000000A6"
    m.top.findNode("panel").color = m.brand.surface
    m.top.findNode("title").color = m.brand.textPrimary

    m.content = m.top.findNode("content")
    m.content.color = m.brand.textSecondary

    m.itemsGroup = m.top.findNode("items")
    m.labels = ["Perfil", "Mi Plan", "Cambiar contraseña", "Cerrar sesión"]
    m.nodes = []

    for each texto in m.labels
        fila = CreateObject("roSGNode", "Group")

        fondo = fila.createChild("Rectangle")
        fondo.width = 648
        fondo.height = 72

        etiqueta = fila.createChild("Label")
        etiqueta.translation = [24, 20]
        etiqueta.width = 600
        etiqueta.font = "font:MediumSystemFont"
        etiqueta.text = texto

        m.itemsGroup.appendChild(fila)
        m.nodes.Push({ bg: fondo, label: etiqueta })
    end for

    m.focusIndex = 0
    applyFocus()
    renderContent(0)

    ' Un Group que recibe el foco se lo queda: hay que delegarlo (docs/ROKU-GOTCHAS.md §21).
    ' Aquí el propio menú es el que gestiona las teclas, así que basta con repintar.
    m.top.observeField("focusedChild", "onFocusReceived")
end sub

sub onFocusReceived()
    if m.top.hasFocus() then applyFocus()
end sub

sub applyFocus()
    for i = 0 to m.nodes.Count() - 1
        if i = m.focusIndex
            m.nodes[i].bg.color = m.brand.focusOutline
            m.nodes[i].label.color = m.brand.pillActiveText
        else
            m.nodes[i].bg.color = m.brand.controlSurface
            m.nodes[i].label.color = m.brand.textPrimary
        end if
    end for
end sub

' El contenido se muestra al MOVERSE, no solo al pulsar OK: con un mando es más cómodo ver la
' información recorriendo la lista que tener que entrar y salir de cada apartado.
sub renderContent(index as integer)
    userInfo = m.global.session
    if not tvHasSession(userInfo)
        m.content.text = "Sesión no disponible"
        return
    end if

    if index = 0
        m.content.text = "USUARIO" + Chr(10) + userInfo.user + Chr(10) + Chr(10) + "CORREO ELECTRÓNICO" + Chr(10) + userInfo.userEmail
        return
    end if

    if index = 1
        texto = "PLAN ASOCIADO" + Chr(10) + userInfo.plan + Chr(10) + Chr(10)

        if userInfo.planes.Count() > 0
            texto = texto + "OTROS PLANES" + Chr(10)
            for each plan in userInfo.planes
                linea = plan.nombre + "  ·  " + Str(plan.cantidadCanales).Trim() + " canales"
                if plan.precio <> "" then linea = linea + "  ·  " + plan.precio + " x mes"
                texto = texto + linea + Chr(10)
            end for
            texto = texto + Chr(10)
        end if

        if userInfo.emailSoporte <> ""
            texto = texto + "Para contratar algún plan, contactar a:" + Chr(10) + userInfo.emailSoporte
        end if

        m.content.text = texto
        return
    end if

    if index = 2
        ' No hay API de cambio de contraseña: es puramente informativo, igual que el original.
        texto = "Si desea cambiar su contraseña, debe solicitarlo al:" + Chr(10) + Chr(10)
        if userInfo.whatsapp <> "" then texto = texto + "WhatsApp: " + userInfo.whatsapp + Chr(10)
        if userInfo.fonoSoporte <> "" then texto = texto + "Teléfono: " + userInfo.fonoSoporte + Chr(10)
        if userInfo.emailSoporte <> "" then texto = texto + userInfo.emailSoporte
        m.content.text = texto
        return
    end if

    m.content.text = "Se cerrará la sesión en este dispositivo."
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if key = "down"
        if m.focusIndex < m.nodes.Count() - 1
            m.focusIndex = m.focusIndex + 1
            applyFocus()
            renderContent(m.focusIndex)
        end if
        return true
    end if

    if key = "up"
        if m.focusIndex > 0
            m.focusIndex = m.focusIndex - 1
            applyFocus()
            renderContent(m.focusIndex)
        end if
        return true
    end if

    if key = "OK"
        if m.focusIndex = 3 then m.top.action = "logout"
        return true
    end if

    if key = "back"
        m.top.action = "close"
        return true
    end if

    return false
end function
