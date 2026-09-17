' CU-19 / CU-20 — Notificaciones (polling cada 60 s; no es push real).
'
' Dos conceptos que NO son lo mismo, y confundirlos fue un bug en el port a Kotlin:
'   - NO LEÍDA  → `read = 0`. Alimenta el contador del icono.
'   - NUEVA     → `created_at` posterior a la última que ya se avisó. Alimenta el aviso flotante.
' Una notificación puede estar sin leer y NO ser nueva (ya se avisó de ella y el usuario la ignoró);
' si se mezclan, el aviso vuelve a saltar en cada ciclo de 60 s.

' La respuesta llega como { message: [...] }. El original le hace `.reverse()` para dejar las más
' nuevas primero, y todo el parseo va dentro de un try/catch que ante cualquier forma rara vacía la
' lista en silencio. Aquí eso es simplemente parseo tolerante.
function tvParseNotifications(json as object) as object
    out = []
    items = jsonArray(json, "message")

    ' Recorrido al revés: las más nuevas quedan primero.
    for i = items.Count() - 1 to 0 step -1
        item = items[i]
        out.Push({
            id: jsonStr(item, "id")
            titulo: jsonStr(item, "title")
            texto: jsonStr(item, "text")
            leida: jsonInt(item, "read") = 1
            createdAt: jsonStr(item, "created_at")
        })
    end for
    return out
end function

function tvCountUnread(notifications as object) as integer
    if notifications = invalid then return 0
    count = 0
    for each n in notifications
        if not n.leida then count = count + 1
    end for
    return count
end function

' Ids a marcar como leídas al abrir el panel (CU-20). Una petición por notificación, sin batch.
function tvUnreadIds(notifications as object) as object
    ids = []
    if notifications = invalid then return ids
    for each n in notifications
        if not n.leida and n.id <> "" then ids.Push(n.id)
    end for
    return ids
end function

' Cuántas son NUEVAS respecto a la última avisada. Sin marca previa, todas las no leídas son nuevas.
' `created_at` viene como "YYYY-MM-DD HH:mm:ss", que se ordena bien comparándolo como texto.
function tvCountNew(notifications as object, lastAlerted as string) as integer
    if notifications = invalid then return 0
    if lastAlerted = "" then return tvCountUnread(notifications)

    count = 0
    for each n in notifications
        if n.createdAt > lastAlerted then count = count + 1
    end for
    return count
end function

' Texto del aviso flotante. Cadena vacía = no hay nada que avisar.
function tvNotificationAlertText(notifications as object, lastAlerted as string) as string
    nuevas = tvCountNew(notifications, lastAlerted)
    if nuevas = 0 then return ""
    if nuevas > 1 then return "Tienes " + Str(nuevas).Trim() + " notificaciones nuevas"

    ' Una sola: se muestra su texto. La lista ya viene con las más nuevas primero, así que es la
    ' PRIMERA no leída, no la última (justo el error que hubo que corregir en el port a Kotlin).
    for each n in notifications
        if not n.leida then return n.texto
    end for
    return ""
end function

' Marca a guardar para no repetir el aviso. La lista viene ordenada de más nueva a más vieja.
function tvLatestCreatedAt(notifications as object) as string
    if notifications = invalid or notifications.Count() = 0 then return ""
    latest = ""
    for each n in notifications
        if n.createdAt > latest then latest = n.createdAt
    end for
    return latest
end function
