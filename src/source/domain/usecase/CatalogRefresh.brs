' CU-17 — Qué hacer con lo que está sonando después de revalidar (cada 60 s).
'
' El backend cambia en caliente (docs/BACKEND-GOTCHAS.md §6): se vio en directo cómo aparecían y
' desaparecían campos, canales y categorías enteras a lo largo de un día. De ahí las dos reglas:
'
'  1. RECONSTRUIR SOLO SI ALGO CAMBIÓ DE VERDAD. Si se redibuja el catálogo en cada ciclo de 60 s se
'     interrumpe la reproducción y se mueve el foco mientras el usuario está navegando, sin motivo.
'  2. RITMO ADAPTATIVO. Si el estado está degradado (sin canal reproducible o sin guía), reintentar
'     más seguido hasta engancharse, y relajar el ritmo al recuperarse.

' Huella del catálogo: cambia si cambia algo que AFECTA a la reproducción o al dibujado. Un cambio
' de, por ejemplo, el logo no debería forzar una reconstrucción, y por eso no entra en la huella.
function tvCatalogSignature(channels as object) as string
    if channels = invalid then return ""
    sig = ""
    for each channel in channels
        sig = sig + Str(channel.cnId).Trim() + "|" + channel.streamUrl + "|" + Str(channel.sectionId).Trim()
        if channel.esAdulto then sig = sig + "|a"
        sig = sig + ";"
    end for
    return sig
end function

function tvCatalogChanged(previousSignature as string, channels as object) as boolean
    return previousSignature <> tvCatalogSignature(channels)
end function

' Decide qué hacer con el canal activo tras el refresco. Devuelve la acción y, si procede, el canal.
'
'   "none"     no hay catálogo: sesión degradada, reintentar antes
'   "switch"   el canal ya no existe → saltar al primer permitido (player.js:1f)
'   "blocked"  sigue existiendo pero se perdió el acceso premium → pausar y mostrar el modal
'   "reload"   misma posición pero la url cambió → recargar el reproductor
'   "keep"     todo igual → NO tocar nada
function tvResolveAfterRefresh(activeChannel as object, currentStreamUrl as string, channels as object, sections as object, premiumsAllowed as object) as object
    if channels = invalid or channels.Count() = 0
        return { action: "none", channel: invalid }
    end if

    if activeChannel = invalid
        return { action: "switch", channel: tvGetFirstAllowedChannel(channels, sections, premiumsAllowed) }
    end if

    found = tvFindChannelByCnId(channels, activeChannel.cnId)
    if found = invalid
        return { action: "switch", channel: tvGetFirstAllowedChannel(channels, sections, premiumsAllowed) }
    end if

    ' El orden importa: primero el permiso, luego la url. Si se perdió el acceso no se debe recargar
    ' el reproductor con la url nueva (player.js:606-626 pausa antes de mostrar el modal).
    if not tvPremiumAllowed(sections, found.sectionId, premiumsAllowed)
        return { action: "blocked", channel: found }
    end if

    if found.streamUrl <> currentStreamUrl
        return { action: "reload", channel: found }
    end if

    return { action: "keep", channel: found }
end function

' Ritmo del refresco. Normal 60 s, igual que el original; degradado 15 s hasta engancharse.
function tvRefreshIntervalSec(hasPlayableChannel as boolean, hasGuide as boolean) as integer
    if hasPlayableChannel and hasGuide then return 60
    return 15
end function

' La guía se reintenta POR SU CUENTA aunque el catálogo no haya cambiado (§7): si solo se refresca
' cuando cambian los canales, la parrilla puede quedarse vacía indefinidamente.
function tvShouldRetryGuide(guideIsEmpty as boolean, catalogChanged as boolean) as boolean
    if guideIsEmpty then return true
    return catalogChanged
end function
