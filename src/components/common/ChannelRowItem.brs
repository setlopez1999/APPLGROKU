' Fila de la parrilla. Ver ChannelRowItem.xml.
'
' ⚠ Toca el dispositivo: no se ejecuta en `npm test`.

sub init()
    m.brand = m.global.brand

    m.rowFocus = m.top.findNode("rowFocus")
    m.rowBg = m.top.findNode("rowBg")
    m.logo = m.top.findNode("logo")
    m.number = m.top.findNode("number")
    m.name = m.top.findNode("name")
    m.cellsGroup = m.top.findNode("cells")

    m.rowFocus.color = m.brand.focusOutline
    m.rowBg.color = m.brand.surface
    m.number.color = m.brand.textSecondary
    m.name.color = m.brand.textPrimary
end sub

sub onContentChanged()
    content = m.top.itemContent
    if content = invalid then return

    ' La lista NO tiene el foco (lo conduce ChannelGrid a mano), así que `focusPercent` siempre
    ' vale 0. El marco lo decide este campo del ContentNode.
    content.observeField("isSelected", "onSelectedChanged")
    content.observeField("selectedCell", "onSelectedCellChanged")
    m.rowFocus.visible = content.isSelected
    m.cellNodes = []

    m.logo.uri = content.logoUri
    m.number.text = content.numero
    m.name.text = content.title

    m.cellsGroup.removeChildrenIndex(m.cellsGroup.getChildCount(), 0)

    cells = content.cells
    if cells = invalid then return
    if cells.Count() = 0 then return

    ' Ancho DINÁMICO. El número de columnas cambia con los datos (de 1 a 5, ver EpgGrid), así que con
    ' un ancho fijo las celdas se salían de la pantalla y la de AHORA quedaba cortada.
    ' Verificado en el simulador el 2026-09-21 con 4 columnas.
    disponible = CELLS_WIDTH() - (cells.Count() - 1) * CELL_SPACING()
    ancho = Int(disponible / cells.Count())
    if ancho < 120 then ancho = 120

    for each cell in cells
        nodo = buildCell(cell, ancho)
        m.cellsGroup.appendChild(nodo)
        m.cellNodes.Push(nodo)
    end for

    onSelectedCellChanged()
end sub

' Espacio horizontal para las celdas: el ancho de la fila menos la zona del canal (logo+nº+nombre).
function CELLS_WIDTH() as integer
    return 1232
end function

function CELL_SPACING() as integer
    return 12
end function

function buildCell(cell as object, ancho as integer) as object
    group = CreateObject("roSGNode", "Group")

    marco = group.createChild("RoundedRect")
    marco.id = "cellFocus"
    marco.shape = "card"
    marco.translation = [-4, -4]
    marco.width = ancho + 8
    marco.height = 96
    marco.color = m.brand.focusOutline
    marco.visible = false

    bg = group.createChild("RoundedRect")
    bg.shape = "card"
    bg.width = ancho
    bg.height = 88

    ' Celda vacía: el canal no tiene programa en esa columna. Se dibuja igual para que la rejilla
    ' quede alineada, pero apagada y sin texto.
    if cell = invalid
        bg.color = m.brand.surfaceVariant
        return group
    end if

    if cell.esAhora
        bg.color = m.brand.accentSoft
    else
        bg.color = m.brand.surfaceVariant
    end if

    titulo = group.createChild("Label")
    titulo.translation = [16, 12]
    titulo.width = ancho - 32
    titulo.font = "font:SmallSystemFont"
    titulo.color = m.brand.textPrimary
    titulo.text = tvCellTitle(cell)

    rango = group.createChild("Label")
    rango.translation = [16, 48]
    rango.width = ancho - 32
    rango.font = "font:SmallestSystemFont"
    rango.color = m.brand.textSecondary
    rango.text = cell.rango

    ' Barra de progreso solo en la celda de AHORA.
    if cell.esAhora
        track = group.createChild("Rectangle")
        track.translation = [16, 76]
        track.width = ancho - 32
        track.height = 4
        track.color = m.brand.surface

        fill = group.createChild("Rectangle")
        fill.translation = [16, 76]
        fill.width = Int(((ancho - 32) * cell.progreso) / 100)
        fill.height = 4
        fill.color = m.brand.liveNow
    end if

    return group
end function

' El ▶ solo aparece cuando la grabación está COMPROBADA con una sonda, no cuando el backend dice que
' existe: el flag `catchup` lo pone un humano y hay canales marcados cuya ruta devuelve 404
' (docs/BACKEND-GOTCHAS.md §3).
function tvCellTitle(cell as object) as string
    if cell.reproducible then return "▶ " + cell.titulo
    return cell.titulo
end function

sub onSelectedChanged()
    content = m.top.itemContent
    if content = invalid then return
    m.rowFocus.visible = content.isSelected
    onSelectedCellChanged()
end sub

' Marco blanco alrededor de la celda con el foco, con el mismo grosor que el resto de la app.
sub onSelectedCellChanged()
    content = m.top.itemContent
    if content = invalid then return
    if m.cellNodes = invalid then return

    seleccionada = content.selectedCell
    for i = 0 to m.cellNodes.Count() - 1
        marco = m.cellNodes[i].findNode("cellFocus")
        if marco <> invalid then marco.visible = (i = seleccionada and content.isSelected)
    end for
end sub
