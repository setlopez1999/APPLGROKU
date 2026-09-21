' Búsqueda de canales. Pantalla "Buscar" de la barra superior (docs/DISENO.md §2.3).
'
' Se busca por NOMBRE y por NÚMERO, porque en una TV la gente hace las dos cosas: teclea "lat" o
' teclea "2". Y sin distinguir mayúsculas ni acentos, que con un teclado en pantalla nadie va a
' molestarse en poner la tilde de "América".

' Normaliza para comparar: minúsculas y sin acentos.
'
' No se usa una tabla Unicode completa a propósito: solo las vocales acentuadas y la eñe, que es lo
' único que aparece en los nombres de canal de estos ISP. Una tabla entera costaría memoria y
' tiempo de arranque en un Roku Express para no ganar nada.
function tvNormalizeForSearch(texto as string) as string
    if texto = "" then return ""

    salida = ""
    minusculas = LCase(texto)

    for i = 1 to Len(minusculas)
        ch = Mid(minusculas, i, 1)
        salida = salida + tvStripAccent(ch)
    end for
    return salida
end function

function tvStripAccent(ch as string) as string
    if ch = "á" or ch = "à" or ch = "ä" or ch = "â" then return "a"
    if ch = "é" or ch = "è" or ch = "ë" or ch = "ê" then return "e"
    if ch = "í" or ch = "ì" or ch = "ï" or ch = "î" then return "i"
    if ch = "ó" or ch = "ò" or ch = "ö" or ch = "ô" then return "o"
    if ch = "ú" or ch = "ù" or ch = "ü" or ch = "û" then return "u"
    if ch = "ñ" then return "n"
    return ch
end function

' Canales que coinciden con la consulta, en el orden del catálogo.
'
' Consulta vacía = lista vacía, NO el catálogo entero: al abrir la pantalla de búsqueda sin escribir
' nada, enseñar los 23 canales haría creer que la búsqueda ya se ejecutó.
function tvSearchChannels(channels as object, query as string) as object
    resultados = []
    if channels = invalid then return resultados

    consulta = tvNormalizeForSearch(query).Trim()
    if consulta = "" then return resultados

    for each channel in channels
        if tvChannelMatches(channel, consulta) then resultados.Push(channel)
    end for
    return resultados
end function

function tvChannelMatches(channel as object, consultaNormalizada as string) as boolean
    if channel = invalid then return false

    ' Por nombre, en cualquier posición: buscar "tina" tiene que encontrar "Latina".
    if Instr(1, tvNormalizeForSearch(channel.nombre), consultaNormalizada) > 0 then return true

    ' Por número, pero solo EXACTO: si "2" trajera el 2, el 12, el 20 y el 21, la lista de números
    ' sería inútil. Quien teclea un número quiere ese canal.
    return Str(channel.numero).Trim() = consultaNormalizada
end function
