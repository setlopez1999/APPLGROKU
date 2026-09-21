' Parrilla de canales. Ver ChannelGrid.xml.
'
' ⚠ Toca el dispositivo: no se ejecuta en `npm test`. La ventana de celdas la construye
' domain/usecase/EpgGrid.brs, que sí está probado.

sub init()
    m.list = m.top.findNode("list")
    m.list.observeField("itemSelected", "onItemSelected")
end sub

sub onDataChanged()
    channels = m.top.channels
    if channels = invalid then return

    window = m.top.epgWindow

    root = CreateObject("roSGNode", "ContentNode")
    for each channel in channels
        row = root.createChild("ContentNode")
        row.addFields({
            title: channel.nombre
            numero: Str(channel.numero).Trim()
            logoUri: channel.imagen
            cnId: channel.cnId
            cells: tvEpgRowForChannel(window, channel.cnId)
        })
    end for

    m.list.content = root
    focusCurrentChannel()
end sub

' Al abrir la parrilla se enfoca el canal QUE SE ESTÁ VIENDO, no el primero de la lista. Era un fix
' explícito del port a Kotlin (CU-06) y se repite aquí porque es lo que espera el usuario.
sub focusCurrentChannel()
    channels = m.top.channels
    if channels = invalid then return

    for i = 0 to channels.Count() - 1
        if channels[i].cnId = m.top.currentCnId
            m.list.jumpToItem = i
            return
        end if
    end for

    m.list.jumpToItem = 0
end sub

sub onGridFocusChanged()
    if m.top.gridFocused then m.list.setFocus(true)
end sub

sub onItemSelected()
    channels = m.top.channels
    if channels = invalid then return

    index = m.list.itemSelected
    if index < 0 or index > channels.Count() - 1 then return

    m.top.chosenCnId = channels[index].cnId
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    ' Arriba en la primera fila: el foco sale hacia las categorías. Sin esto, el usuario se queda
    ' atrapado en la parrilla — el fallo exacto que documentaron en el port a tvOS.
    if key = "up" and m.list.itemFocused = 0 then return false

    return false
end function
