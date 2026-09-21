' Píldoras de categoría. Ver CategoryTabs.xml.
'
' ⚠ Toca el dispositivo: no se ejecuta en `npm test`.

sub init()
    m.brand = m.global.brand
    m.pills = m.top.findNode("pills")
    m.nodes = []
    m.focusIndex = 0
end sub

sub onCategoriesChanged()
    m.pills.removeChildrenIndex(m.pills.getChildCount(), 0)
    m.nodes = []

    categories = m.top.categories
    if categories = invalid then return

    for i = 0 to categories.Count() - 1
        pill = CreateObject("roSGNode", "Group")

        bg = pill.createChild("RoundedRect")
        bg.id = "pillBg"
        bg.shape = "pill"
        bg.height = 64

        label = pill.createChild("Label")
        label.id = "pillLabel"
        label.text = categories[i]
        label.font = "font:MediumSystemFont"
        label.translation = [28, 16]

        ' El ancho del texto no se conoce hasta que se mide: boundingRect() lo da ya renderizado.
        ancho = label.boundingRect().width + 56
        if ancho < 140 then ancho = 140
        bg.width = ancho

        m.pills.appendChild(pill)
        m.nodes.Push({ bg: bg, label: label })
    end for

    ' Al cambiar de catálogo, el foco vuelve al principio para no quedar fuera de rango.
    if m.focusIndex > m.nodes.Count() - 1 then m.focusIndex = 0
    onSelectionChanged()
end sub

sub onSelectionChanged()
    for i = 0 to m.nodes.Count() - 1
        node = m.nodes[i]
        seleccionada = (i = m.top.selectedIndex)
        enfocada = m.top.barFocused and i = m.focusIndex

        if seleccionada
            ' La activa es blanca con texto oscuro (DISENO §1).
            node.bg.color = m.brand.pillActive
            node.label.color = m.brand.pillActiveText
        else
            ' El resto, "glass": translúcidas para que se vea el vídeo detrás.
            node.bg.color = m.brand.controlSurface
            node.label.color = m.brand.textSecondary
        end if

        ' El marco de foco es blanco y va aparte del estado de selección: se puede estar enfocando
        ' una categoría distinta de la que está aplicada.
        if enfocada
            node.bg.color = m.brand.focusOutline
            node.label.color = m.brand.pillActiveText
        end if
    end for
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.nodes.Count() = 0 then return false

    if key = "right"
        if m.focusIndex < m.nodes.Count() - 1
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
        m.top.chosenIndex = m.focusIndex
        return true
    end if

    ' Arriba y abajo NO se consumen: el foco tiene que poder salir de la fila. Consumirlos es la
    ' forma clásica de dejar la mitad de la pantalla inalcanzable (arquitectura_flujo.md §5).
    return false
end function
