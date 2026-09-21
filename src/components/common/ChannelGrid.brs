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
        m.rows[i].isSelected = (i = m.focusIndex and m.top.gridFocused)
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
        applyFocusIndex()
        return true
    end if

    if key = "up"
        if m.focusIndex <= 0 then return false                    ' primero: sale hacia las categorías
        m.focusIndex = m.focusIndex - 1
        applyFocusIndex()
        return true
    end if

    if key = "OK"
        channels = m.top.channels
        if channels <> invalid and m.focusIndex <= channels.Count() - 1
            m.top.chosenCnId = channels[m.focusIndex].cnId
        end if
        return true
    end if

    return false
end function
