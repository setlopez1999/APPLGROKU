' Buscar canales. Ver SearchScreen.xml.
'
' ⚠ Toca el dispositivo: no se ejecuta en `npm test`. El filtrado está en
' domain/usecase/Search.brs, que sí tiene tests.

sub init()
    m.brand = m.global.brand
    m.top.findNode("bg").color = m.brand.background
    m.top.findNode("titulo").color = m.brand.textPrimary
    m.top.findNode("pista").color = m.brand.textSecondary

    m.resumen = m.top.findNode("resumen")
    m.resumen.color = m.brand.textSecondary

    m.teclado = m.top.findNode("teclado")
    ' Se busca según se escribe: en una TV, obligar a confirmar cada búsqueda es un paso de más.
    m.teclado.observeField("text", "onQuery")

    m.grid = m.top.findNode("grid")
    m.grid.observeField("chosenCnId", "onChosen")

    m.resultados = []
    m.enResultados = false

    m.top.observeField("focusedChild", "onFocusReceived")
end sub

sub onFocusReceived()
    if not m.top.hasFocus() then return
    m.enResultados = false
    m.grid.gridFocused = false
    m.teclado.setFocus(true)
end sub

sub onQuery()
    m.resultados = tvSearchChannels(m.top.channels, m.teclado.text)

    if m.teclado.text.Trim() = ""
        m.resumen.text = ""
    else if m.resultados.Count() = 0
        m.resumen.text = "Sin resultados para """ + m.teclado.text + """"
    else
        m.resumen.text = Str(m.resultados.Count()).Trim() + " canal(es)"
    end if

    m.grid.visible = (m.resultados.Count() > 0)
    if m.resultados.Count() > 0
        m.grid.epgWindow = m.top.epgWindow
        m.grid.channels = m.resultados
    end if
end sub

sub onChosen()
    m.top.chosenCnId = m.grid.chosenCnId
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    ' ABAJO baja del teclado a los resultados, ARRIBA vuelve. El teclado se queda las flechas
    ' mientras tiene el foco (docs/ROKU-GOTCHAS.md §21), así que el salto se decide aquí.
    if key = "down" and not m.enResultados and m.resultados.Count() > 0
        m.enResultados = true
        m.grid.gridFocused = true
        return true
    end if

    if key = "up" and m.enResultados
        m.enResultados = false
        m.grid.gridFocused = false
        m.teclado.setFocus(true)
        return true
    end if

    return false
end function
