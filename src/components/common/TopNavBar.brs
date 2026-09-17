' Barra superior. Ver TopNavBar.xml.
'
' ⚠ Toca el dispositivo: no se ejecuta en `npm test`. La regla de qué pestaña se dibuja y cómo sí
' está probada, en domain/usecase/Tabs.brs.

sub init()
    m.brand = m.global.brand

    m.logo = m.top.findNode("logo")
    m.logo.uri = m.brand.logoUri

    ' Si no hay imagen de logo, se cae al nombre en texto con estilo de marca (igual que el Kotlin).
    m.logoText = m.top.findNode("logoText")
    m.logoText.text = m.brand.appName
    m.logoText.color = m.brand.textPrimary
    m.logoText.visible = (m.brand.logoUri = "")

    m.tabsGroup = m.top.findNode("tabsGroup")
    m.iconsGroup = m.top.findNode("iconsGroup")

    ' Orden fijo de izquierda a derecha, igual que el rediseño.
    m.tabOrder = ["home", "live", "events", "content"]
    m.tabTitles = { home: "Inicio", live: "TV en directo", events: "Eventos", content: "Contenidos" }

    ' Buscar y Mi lista quedan visibles pero apagados hasta que tengan pantalla real.
    m.iconOrder = ["search", "mylist", "profile"]
    m.iconTitles = { search: "Buscar", mylist: "Mi lista", profile: "Perfil" }
    m.iconEnabled = { search: false, mylist: true, profile: true }

    m.focusIndex = 0
    m.items = []

    buildIcons()
end sub

sub onTabsChanged()
    buildTabs()
    onSelectionChanged()
end sub

sub buildTabs()
    m.tabsGroup.removeChildrenIndex(m.tabsGroup.getChildCount(), 0)
    m.items = []

    tabs = m.top.tabs
    if tabs = invalid then return

    ' Una sola pestaña visible no aporta navegación: mejor barra limpia.
    if not tvShouldDrawTabs(tabs)
        buildFocusList()
        return
    end if

    for each id in m.tabOrder
        state = tabs[id]
        if state <> invalid and state <> TAB_HIDDEN()
            label = CreateObject("roSGNode", "Label")
            label.id = "tab_" + id
            label.text = m.tabTitles[id]
            label.font = "font:MediumSystemFont"
            m.tabsGroup.appendChild(label)
            m.items.Push({ kind: "tab", id: id, node: label, enabled: state = TAB_ENABLED() })
        end if
    end for

    buildFocusList()
end sub

sub buildIcons()
    for each id in m.iconOrder
        label = CreateObject("roSGNode", "Label")
        label.id = "icon_" + id
        label.text = m.iconTitles[id]
        label.font = "font:SmallSystemFont"
        m.iconsGroup.appendChild(label)
    end for
end sub

' Los iconos van SIEMPRE al final de la lista de foco, después de las pestañas.
sub buildFocusList()
    for each id in m.iconOrder
        node = m.top.findNode("icon_" + id)
        if node <> invalid
            m.items.Push({ kind: "icon", id: id, node: node, enabled: m.iconEnabled[id] })
        end if
    end for

    if m.focusIndex > m.items.Count() - 1 then m.focusIndex = 0
end sub

' Colores: seleccionada en blanco, deshabilitada en gris apagado, con foco en el color de foco.
sub onSelectionChanged()
    for i = 0 to m.items.Count() - 1
        item = m.items[i]
        selected = (item.kind = "tab" and item.id = m.top.selectedTab)
        focused = m.top.barFocused and i = m.focusIndex

        if focused
            item.node.color = m.brand.focusOutline
        else if not item.enabled
            item.node.color = m.brand.textDisabled
        else if selected
            item.node.color = m.brand.textPrimary
        else
            item.node.color = m.brand.textSecondary
        end if
    end for
end sub

' La barra no se queda el foco: lo devuelve a la pantalla cuando se sale por abajo. Quien la usa
' decide qué hacer con `action`.
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.items.Count() = 0 then return false

    if key = "right"
        if m.focusIndex < m.items.Count() - 1
            m.focusIndex = m.focusIndex + 1
            onSelectionChanged()
        end if
        return true
    end if

    if key = "left"
        if m.focusIndex > 0
            m.focusIndex = m.focusIndex - 1
            onSelectionChanged()
        end if
        return true
    end if

    if key = "OK"
        item = m.items[m.focusIndex]
        ' Una pestaña gris se dibuja pero no hace nada: el backend la manda apagada.
        if not item.enabled then return true
        m.top.action = item.id
        return true
    end if

    return false
end function
