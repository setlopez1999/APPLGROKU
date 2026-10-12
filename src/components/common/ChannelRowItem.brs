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
    m.viewport = m.top.findNode("cellsViewport")
    m.track = m.top.findNode("cellsTrack")

    ' RECORTE. Sin esto las celdas que quedan fuera de la ventana se dibujan encima de la columna
    ' del canal y se salen por el borde derecho de la pantalla.
    anchoVentana = tvEpgVisibleColumns() * tvEpgCellStride()
    m.viewport.clippingRect = [0, 0, anchoVentana, 92]

    m.firstColumn = 0
    m.nowColumn = 0

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

    m.track.removeChildrenIndex(m.track.getChildCount(), 0)

    cells = content.cells
    if cells = invalid then return
    if cells.Count() = 0 then return

    ' Ancho FIJO por celda, no repartido entre todas: la fila se desplaza en horizontal, así que
    ' las columnas no pueden encogerse para caber. Con 5 columnas repartidas el título se cortaba
    ' a la tercera letra (visto en el Roku Express el 2026-10-12).
    paso = tvEpgCellStride()
    ancho = paso - CELL_GAP() * 2

    ' Dónde está la celda de AHORA: es la que se encuadra cuando la fila está en reposo.
    m.nowColumn = 0
    for i = 0 to cells.Count() - 1
        if cells[i] <> invalid and cells[i].esAhora
            m.nowColumn = i
            exit for
        end if
    end for

    for i = 0 to cells.Count() - 1
        nodo = buildCell(cells[i], ancho)
        nodo.translation = [i * paso + CELL_GAP(), 0]
        m.track.appendChild(nodo)
        m.cellNodes.Push(nodo)
    end for

    m.firstColumn = tvEpgFirstVisibleColumn(-1, m.nowColumn, cells.Count())
    applyScroll()
    onSelectedCellChanged()
end sub

' Hueco a cada lado de la celda dentro de su paso (4 dp del rediseño).
function CELL_GAP() as integer
    return 8
end function

' Desplaza la pista de celdas para que la columna `m.firstColumn` quede pegada al borde izquierdo
' de la ventana.
sub applyScroll()
    m.track.translation = [-m.firstColumn * tvEpgCellStride(), 0]
end sub

function buildCell(cell as object, ancho as integer) as object
    group = CreateObject("roSGNode", "Group")

    marco = group.createChild("RoundedRect")
    marco.id = "cellFocus"
    marco.shape = "card"
    marco.translation = [-4, -4]
    marco.width = ancho + 8
    marco.height = 88
    marco.color = m.brand.focusOutline
    marco.visible = false

    bg = group.createChild("RoundedRect")
    bg.shape = "card"
    bg.width = ancho
    bg.height = 80

    ' Celda vacía: el canal no tiene programa en esa columna. Se dibuja igual para que la rejilla
    ' quede alineada, pero apagada y sin texto.
    if cell = invalid
        bg.color = m.brand.surfaceVariant
        return group
    end if

    ' La celda AHORA ya NO se distingue por el FONDO.
    '
    ' Antes llevaba el fondo del color del ISP, y al enfocarla el marco blanco la tapaba: la celda
    ' perdia su marca justo al seleccionarla, y el usuario creia haber perdido algo. Como el foco
    ' pisa el fondo, la senal de "al aire" se mueve al TEXTO, que el foco no toca.
    ' Mismo cambio que el rediseno Kotlin (9056160, verificado en TV real).
    bg.color = m.brand.surfaceVariant

    titulo = group.createChild("Label")
    titulo.translation = [16, 12]
    titulo.width = ancho - 32
    titulo.font = "font:SmallSystemFont"
    titulo.text = tvCellTitle(cell)

    ' El color es el acento DERIVADO (mezclado hacia blanco), no el crudo: el verde de Oneplay
    ' (#00BB5F) sobre el gris de la celda se lee justo, y el de Playcom ya es claro. Derivarlo deja
    ' el texto legible con CUALQUIER color de marca, sin ajustar nada por ISP.
    if cell.esAhora
        titulo.color = m.brand.accentText
    else
        titulo.color = m.brand.textPrimary
    end if

    rango = group.createChild("Label")
    rango.translation = [16, 44]
    rango.width = ancho - 32
    rango.font = "font:SmallestSystemFont"
    rango.color = m.brand.textSecondary
    rango.text = cell.rango

    ' Barra de progreso solo en la celda de AHORA.
    if cell.esAhora
        track = group.createChild("Rectangle")
        track.translation = [16, 70]
        track.width = ancho - 32
        track.height = 4
        track.color = m.brand.surface

        fill = group.createChild("Rectangle")
        fill.translation = [16, 70]
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

    ' La fila se desplaza lo MÍNIMO para traer la celda enfocada: recentrar en cada pulsación
    ' movería toda la parrilla bajo el dedo del usuario. Cuando la fila pierde el foco vuelve al
    ' encuadre de reposo, con AHORA en el centro.
    if content.isSelected
        m.firstColumn = tvEpgScrollTo(m.firstColumn, seleccionada, m.nowColumn, m.cellNodes.Count())
    else
        m.firstColumn = tvEpgFirstVisibleColumn(-1, m.nowColumn, m.cellNodes.Count())
    end if
    applyScroll()

    for i = 0 to m.cellNodes.Count() - 1
        marco = m.cellNodes[i].findNode("cellFocus")
        if marco <> invalid then marco.visible = (i = seleccionada and content.isSelected)
    end for
end sub
