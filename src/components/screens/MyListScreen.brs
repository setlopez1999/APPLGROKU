' CU-09 — Mi lista. Ver MyListScreen.xml.
'
' ⚠ Toca el dispositivo: no se ejecuta en `npm test`. El cruce favoritos × catálogo lo hace
' domain/usecase/Favorites.brs, que sí tiene tests.

sub init()
    m.brand = m.global.brand
    m.top.findNode("bg").color = m.brand.background
    m.top.findNode("titulo").color = m.brand.textPrimary

    m.vacio = m.top.findNode("vacio")
    m.vacio.color = m.brand.textSecondary

    m.grid = m.top.findNode("grid")
    m.grid.observeField("chosenCnId", "onChosen")

    m.top.observeField("focusedChild", "onFocusReceived")
end sub

sub onFocusReceived()
    if not m.top.hasFocus() then return
    ' Sin canales no hay nada que enfocar: el foco se queda aquí y el ATRÁS cierra la pantalla.
    if m.top.channels <> invalid and m.top.channels.Count() > 0 then m.grid.gridFocused = true
end sub

sub onChannels()
    canales = m.top.channels
    if canales = invalid then canales = []

    hay = (canales.Count() > 0)
    m.vacio.visible = not hay
    m.grid.visible = hay

    if hay
        m.grid.currentCnId = m.top.currentCnId
        m.grid.epgWindow = m.top.epgWindow
        m.grid.channels = canales
    end if
end sub

sub onChosen()
    m.top.chosenCnId = m.grid.chosenCnId
end sub
