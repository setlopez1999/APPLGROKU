' Reglas de acceso a un canal: premium (CU-15) y primer canal permitido (CU-05).

' ¿Puede el usuario ver esta sección?
'  - la sección no es premium            → sí
'  - es premium y está en su plan        → sí
'  - es premium y NO está                → no
'  - la sección no existe en la lista    → no (mismo criterio que player.js:125-148)
function tvPremiumAllowed(sections as object, sectionId as integer, premiumsAllowed as object) as boolean
    found = invalid
    for each section in sections
        if section.stId = sectionId
            found = section
            exit for
        end if
    end for

    if found = invalid then return false
    if found.premium <> 1 then return true

    if premiumsAllowed = invalid then return false
    for each id in premiumsAllowed
        if Int(id) = sectionId then return true
    end for
    return false
end function

' Primer canal reproducible al arrancar: ni premium bloqueado ni adulto.
' Si ninguno pasa, cae al primero de la lista — igual que el original (player.js:482-498), que
' prefiere intentar algo antes que dejar la pantalla en negro.
' Si no hay canales, devuelve invalid: el llamador decide (sesión degradada, reintentar).
function tvGetFirstAllowedChannel(channels as object, sections as object, premiumsAllowed as object) as object
    if channels = invalid or channels.Count() = 0 then return invalid

    for each channel in channels
        if tvPremiumAllowed(sections, channel.sectionId, premiumsAllowed) and not channel.esAdulto
            return channel
        end if
    end for

    return channels[0]
end function

function tvFindChannelByCnId(channels as object, cnId as integer) as object
    if channels = invalid then return invalid
    for each channel in channels
        if channel.cnId = cnId then return channel
    end for
    return invalid
end function
