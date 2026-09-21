' Parrilla de canales. Ver ChannelGrid.xml.
'
' ⚠ Toca el dispositivo: no se ejecuta en `npm test`. La ventana de celdas la construye
' domain/usecase/EpgGrid.brs, que sí está probado.
'
' POR QUÉ EL FOCO SE CONDUCE A MANO (verificado en el simulador el 2026-09-21):
' si el `MarkupList` tiene el foco, se queda TODAS las flechas verticales y no las propaga ni
' estando en la primera fila. El usuario quedaba atrapado en la parrilla, sin poder subir a las
' categorías — exactamente el fallo que documentaron en el port a tvOS.
' Solución: el foco lo tiene este Group, la lista se desplaza con `jumpToItem`, y en los bordes se
' devuelve `false` para que la tecla suba a LiveScreen. Ver docs/ROKU-GOTCHAS.md §21.

sub init()
    m.list = m.top.findNode("list")
    m.focusIndex = 0
    m.cellIndex = -1   ' -1 = el foco esta en el canal, no en una celda
    m.rows = []
end sub

sub onDataChanged()
    channels = m.top.channels
    if channels = invalid then return

    window = m.top.epgWindow

    root = CreateObject("roSGNode", "ContentNode")
    m.rows = []
    for each channel in channels
        row = root.createChild("ContentNode")
        row.addFields({
            title: channel.nombre
            numero: Str(channel.numero).Trim()
            logoUri: channel.imagen
            cnId: channel.cnId
            cells: tvEpgRowForChannel(window, channel.cnId)
            ' Celda resaltada dentro de la fila (-1 = ninguna)
            selectedCell: -1
            ' El marco de foco lo pinta la fila leyendo este campo: como la lista no tiene el foco,
            ' no se puede usar su `focusPercent`.
            isSelected: false
        })
        m.rows.Push(row)
    end for

    m.list.content = root
    focusCurrentChannel()
end sub

' Al abrir la parrilla se enfoca el canal QUE SE ESTÁ VIENDO, no el primero de la lista. Era un fix
' explícito del port a Kotlin (CU-06) y se repite aquí porque es lo que espera el usuario.
sub focusCurrentChannel()
    channels = m.top.channels
    if channels = invalid or channels.Count() = 0 then return

    m.focusIndex = 0
    for i = 0 to channels.Count() - 1
        if channels[i].cnId = m.top.currentCnId
            m.focusIndex = i
            exit for
        end if
    end for

    applyFocusIndex()
end sub

sub applyFocusIndex()
    m.list.jumpToItem = m.focusIndex

    for i = 0 to m.rows.Count() - 1
        enfocada = (i = m.focusIndex and m.top.gridFocused)
        m.rows[i].isSelected = enfocada
        if enfocada
            m.rows[i].selectedCell = m.cellIndex
        else
            m.rows[i].selectedCell = -1
        end if
    end for
end sub

sub onGridFocusChanged()
    if m.top.gridFocused then m.top.setFocus(true)
    applyFocusIndex()
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.rows.Count() = 0 then return false

    if key = "down"
        if m.focusIndex >= m.rows.Count() - 1 then return false   ' último: la tecla sube a LiveScreen
        m.focusIndex = m.focusIndex + 1
        m.cellIndex = -1
        applyFocusIndex()
        return true
    end if

    if key = "up"
        if m.focusIndex <= 0 then return false                    ' primero: sale hacia las categorías
        m.focusIndex = m.focusIndex - 1
        m.cellIndex = -1
        applyFocusIndex()
        return true
    end if

    if key = "right"
        if m.cellIndex < cellCount() - 1
            m.cellIndex = m.cellIndex + 1
            applyFocusIndex()
        end if
        return true
    end if

    if key = "left"
        if m.cellIndex >= 0
            m.cellIndex = m.cellIndex - 1
            applyFocusIndex()
            return true
        end if
        return false   ' ya estaba en el canal: la tecla sale de la parrilla
    end if

    if key = "OK"
        channels = m.top.channels
        if channels = invalid or m.focusIndex > channels.Count() - 1 then return true
        channel = channels[m.focusIndex]

        ' Sobre una celda PASADA con grabacion comprobada se reproduce la grabacion; en cualquier
        ' otro caso se sintoniza el canal en vivo (docs/DISENO.md 2.4).
        celda = currentCell()
        if celda <> invalid and celda.reproducible
            m.top.chosenCatchup = { url: celda.catchupUrl, titulo: celda.titulo, cnId: channel.cnId }
            return true
        end if

        m.top.chosenCnId = channel.cnId
        return true
    end if

    return false
end function

function cellCount() as integer
    if m.focusIndex > m.rows.Count() - 1 then return 0
    celdas = m.rows[m.focusIndex].cells
    if celdas = invalid then return 0
    return celdas.Count()
end function

function currentCell() as object
    if m.cellIndex < 0 then return invalid
    if m.focusIndex > m.rows.Count() - 1 then return invalid
    celdas = m.rows[m.focusIndex].cells
    if celdas = invalid or m.cellIndex > celdas.Count() - 1 then return invalid
    return celdas[m.cellIndex]
end function
