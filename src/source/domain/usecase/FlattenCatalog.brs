' Aplana el catálogo de get-web2 (categorías → secciones → canales) a dos listas planas, y de paso
' aplica las tres reglas que deciden si la app funciona o muestra pestañas muertas.
'
' Estructura de entrada (docs/BACKEND-GOTCHAS.md §12):
'   get-web2.sections[]        ← categorías raíz
'     └── sections[]           ← secciones reales (Nacionales, Musicales…)
'           └── canales[]      ← los canales
'
' Reglas aplicadas aquí (NO en la vista):
'  1. La url efectiva se resuelve ANTES de filtrar. Con multi-CDN es multiCdnUrl + shortLink, así que
'     un canal con `url` vacía SÍ puede ser reproducible por esa vía. Filtrar por la url cruda
'     borraría canales válidos (§5).
'  2. Canal sin url resuelta → fuera. El backend devuelve TODOS los canales del ISP, incluidos los
'     que el cliente no tiene contratados, y esos llegan con `url: ""` (§5). Una cadena vacía no es
'     invalid: pasa los guards ingenuos, el reproductor falla, y con reintento automático se queda
'     reintentando la misma url vacía para siempre.
'  3. Sección que se queda sin canales → fuera. Si no, se dibujan pestañas que al abrirlas no
'     reproducen nada (el plan del cliente se aplica por categoría completa, todo o nada).
'
' El flag de adulto puede venir en el CANAL (`adulto`) y no solo en la sección — verificado contra
' respuesta real durante el port a Kotlin. Se marca adulto si lo dice CUALQUIERA de los dos.

function tvFlattenCatalog(getWeb2 as object, multiCdnUrl = "" as string, hideAdult = false as boolean) as object
    sectionsOut = []
    channelsOut = []
    categoryIndex = 0

    for each category in jsonArray(getWeb2, "sections")
        for each rawSection in jsonArray(category, "sections")
            section = SectionFromJson(rawSection)

            ' Sección adulta oculta: no se incrementa categoryIndex, la sección no existe para la app.
            if not (hideAdult and section.adulto = 1)
                sectionChannels = []

                for each rawChannel in section.canales
                    channel = ChannelFromJson(rawChannel)
                    channel.streamUrl = tvResolveStreamUrl(channel, multiCdnUrl)

                    if channel.streamUrl <> ""
                        channel.sectionId = section.stId
                        channel.sectionNombre = section.nombre
                        channel.sectionPremium = section.premium
                        channel.sectionAdulto = section.adulto
                        channel.esAdulto = (channel.adulto = 1 or section.adulto = 1)

                        if not (hideAdult and channel.esAdulto)
                            sectionChannels.Push(channel)
                        end if
                    end if
                end for

                if sectionChannels.Count() > 0
                    section.categoryIndex = categoryIndex
                    section.canales = sectionChannels
                    sectionsOut.Push(section)
                    categoryIndex = categoryIndex + 1

                    for each c in sectionChannels
                        channelsOut.Push(c)
                    end for
                end if
            end if
        end for
    end for

    return { sections: sectionsOut, channels: channelsOut }
end function

' Con multi-CDN activo la url se arma desde el shortLink; si no, es la del backend.
' Si multi-CDN está activo pero el canal no trae shortLink, cae a la url cruda en vez de devolver
' una url a medias (que sería peor que no tener ninguna).
function tvResolveStreamUrl(channel as object, multiCdnUrl as string) as string
    if multiCdnUrl <> "" and channel.shortLink <> ""
        return multiCdnUrl + channel.shortLink
    end if
    return channel.url
end function

' Canales de una categoría por su índice (el que asigna el aplanado).
function tvChannelsForCategory(sections as object, categoryIndex as integer) as object
    for each section in sections
        if section.categoryIndex = categoryIndex then return section.canales
    end for
    return []
end function

' Índice de categoría al que pertenece un canal — para sincronizar la pestaña con lo que se
' reproduce al abrir la lista (player.js:171,1424).
function tvCategoryIndexForChannel(sections as object, channel as object) as integer
    if channel = invalid then return 0
    for each section in sections
        if section.stId = channel.sectionId then return section.categoryIndex
    end for
    return 0
end function
