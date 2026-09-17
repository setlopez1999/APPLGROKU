' CU-08 / CU-09 — Favoritos ("Mi lista").
'
' Los tres endpoints son POST con los parámetros en el query string, y `delete-favorite` es POST y no
' DELETE (ver data/remote/ApiRoutes.brs). Aquí solo vive la lógica: qué operación toca y qué se pinta.

' Respuesta de api/get-favorite → { channels: [ { cn_id, ... } ] }
function tvParseFavoriteIds(json as object) as object
    ids = []
    for each channel in jsonArray(json, "channels")
        cnId = jsonInt(channel, "cn_id")
        if cnId > 0 then ids.Push(cnId)
    end for
    return ids
end function

function tvIsFavorite(favoriteIds as object, cnId as integer) as boolean
    if favoriteIds = invalid then return false
    for each id in favoriteIds
        if Int(id) = cnId then return true
    end for
    return false
end function

' Qué llamada toca: si ya es favorito se quita, si no se añade.
function tvToggleFavoriteAction(favoriteIds as object, cnId as integer) as string
    if tvIsFavorite(favoriteIds, cnId) then return "delete"
    return "add"
end function

' Actualización local optimista, para que la estrella responda al instante sin esperar al servidor.
' La lista de verdad la sigue mandando `get-favorite` en el siguiente refresco.
function tvToggleFavoriteLocal(favoriteIds as object, cnId as integer) as object
    out = []
    removed = false
    if favoriteIds <> invalid
        for each id in favoriteIds
            if Int(id) = cnId
                removed = true
            else
                out.Push(Int(id))
            end if
        end for
    end if
    if not removed then out.Push(cnId)
    return out
end function

' Cruce favoritos × catálogo vigente, conservando el orden del catálogo.
'
' Los favoritos que ya no están en la lista activa se SALTAN en silencio (player.js:1541): el canal
' puede haber salido del plan del cliente o haberlo quitado el ISP, y pintar un favorito que no se
' puede reproducir es peor que no pintarlo.
function tvFavoriteChannels(favoriteIds as object, channels as object) as object
    out = []
    if channels = invalid or favoriteIds = invalid then return out
    for each channel in channels
        if tvIsFavorite(favoriteIds, channel.cnId) then out.Push(channel)
    end for
    return out
end function
