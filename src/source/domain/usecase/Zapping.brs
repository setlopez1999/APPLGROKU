' CU-11 — Zapping con ↑↓.
'
' BUG DEL ORIGINAL QUE NO SE REPLICA: `zapping()` (player.js:647-685) se llama a sí mismo de forma
' recursiva para saltar los canales premium/adultos. Si TODOS los canales de la lista son premium o
' adultos, la recursión no termina nunca — no hay protección. Aquí es un BUCLE con tope igual al
' número de canales, y si ninguno sirve devuelve invalid para que el llamador decida.
'
' Nota de plataforma: el original tiene DOS disparadores (flechas y botones CH+/CH-) con guards
' distintos. El mando de Roku NO tiene botones de canal, así que aquí solo existe el de flechas
' (docs/ROKU-GOTCHAS.md §6). La lógica de búsqueda es la misma.

function tvFindNextChannel(channels as object, currentCnId as integer, goingDown as boolean, sections as object, premiumsAllowed as object) as object
    if channels = invalid or channels.Count() = 0 then return invalid

    total = channels.Count()
    index = tvIndexOfChannel(channels, currentCnId)

    ' Si el canal actual ya no está en la lista (el backend lo quitó), se arranca desde el principio.
    if index < 0 then index = 0

    for attempt = 1 to total
        if goingDown
            index = index + 1
            if index > total - 1 then index = 0          ' vuelta al primero
        else
            index = index - 1
            if index < 0 then index = total - 1          ' vuelta al último
        end if

        candidate = channels[index]
        if tvPremiumAllowed(sections, candidate.sectionId, premiumsAllowed) and not candidate.esAdulto
            return candidate
        end if
    end for

    ' Ningún canal reproducible en toda la lista. Aquí es donde el original desbordaba la pila.
    return invalid
end function

function tvIndexOfChannel(channels as object, cnId as integer) as integer
    for i = 0 to channels.Count() - 1
        if channels[i].cnId = cnId then return i
    end for
    return -1
end function
