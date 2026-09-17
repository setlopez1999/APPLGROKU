sub testFlattenCatalog()
    tvSuite("domain/usecase/FlattenCatalog — las 3 reglas del plan del cliente (BACKEND-GOTCHAS §5)")

    r = tvFlattenCatalog(fxGetWeb2())

    ' Regla 2: canales sin url resuelta fuera. Deportes tiene 2 canales, ambos con url vacía.
    tvAssertInvalid(tvFindChannelByCnId(r.channels, 201), "canal con url vacía se filtra")
    tvAssertInvalid(tvFindChannelByCnId(r.channels, 202), "el segundo canal sin url también")

    ' Regla 3: la sección que se queda sin canales desaparece (si no, pestaña que no reproduce nada)
    deportes = false
    for each s in r.sections
        if s.stId = 20 then deportes = true
    end for
    tvAssertEqual(deportes, false, "la categoría que queda vacía no se dibuja")

    ' Lo que sí sobrevive
    tvAssertEqual(r.sections.Count(), 4, "quedan 4 secciones (Nacionales, Cine, Adultos, Mixta)")
    tvAssertEqual(r.channels.Count(), 6, "quedan 6 canales con url")

    ' categoryIndex consecutivo y sin huecos, pese a haber saltado Deportes
    idx = []
    for each s in r.sections
        idx.Push(s.categoryIndex)
    end for
    tvAssertEqual(idx[0], 0, "primera categoría con índice 0")
    tvAssertEqual(idx[1], 1, "la categoría saltada no deja hueco en el índice")
    tvAssertEqual(idx[3], 3, "índices consecutivos hasta el final")

    ' Campos copiados de la sección al canal
    nativa = tvFindChannelByCnId(r.channels, 101)
    tvAssertEqual(nativa.sectionId, 10, "el canal hereda el st_id de su sección")
    tvAssertEqual(nativa.sectionNombre, "Nacionales", "el canal hereda el nombre de la sección")
    tvAssertEqual(nativa.streamUrl, nativa.url, "sin multi-CDN la url efectiva es la del backend")

    ' Adulto: por sección y por canal
    xxx = tvFindChannelByCnId(r.channels, 401)
    tvAssertEqual(xxx.esAdulto, true, "canal de sección adulta se marca adulto")
    picante = tvFindChannelByCnId(r.channels, 502)
    tvAssertEqual(picante.esAdulto, true, "canal con `adulto` SOLO en el canal también se marca")
    normal = tvFindChannelByCnId(r.channels, 501)
    tvAssertEqual(normal.esAdulto, false, "su vecino de la misma sección NO se marca")

    tvSuite("FlattenCatalog — multi-CDN (CU-12)")

    ' Regla 1: la url se resuelve ANTES de filtrar. Filtrar por la url cruda borraría canales válidos.
    cdn = tvFlattenCatalog(fxGetWeb2(), "https://cdn.isp.tv/live/")
    nativaCdn = tvFindChannelByCnId(cdn.channels, 101)
    tvAssertEqual(nativaCdn.streamUrl, "https://cdn.isp.tv/live/nativa", "con multi-CDN la url es cdn + short_link")

    ' Un canal SIN url cruda pero CON short_link sí es reproducible por multi-CDN
    conShortLink = { sections: [ { st_id: 1, nombre: "C", sections: [ { st_id: 10, nombre: "S", canales: [ { cn_id: 1, nombre: "X", url: "", short_link: "equis" } ] } ] } ] }
    r2 = tvFlattenCatalog(conShortLink, "https://cdn.isp.tv/live/")
    tvAssertEqual(r2.channels.Count(), 1, "canal sin url cruda pero con short_link NO se borra si hay multi-CDN")
    tvAssertEqual(r2.channels[0].streamUrl, "https://cdn.isp.tv/live/equis", "y su url se arma con el CDN")

    ' El mismo canal sin multi-CDN sí desaparece
    r3 = tvFlattenCatalog(conShortLink)
    tvAssertEqual(r3.channels.Count(), 0, "el mismo canal sin multi-CDN sí se filtra")

    tvSuite("FlattenCatalog — degradado y adulto oculto")

    ' Respuesta a medias: no debe reventar (§6)
    d = tvFlattenCatalog(fxGetWeb2Degradado())
    tvAssertEqual(d.channels.Count(), 1, "respuesta sin premium/adulto/catchup se parsea igual")
    tvAssertEqual(d.channels[0].catchup, 0, "campo `catchup` ausente vale 0, no rompe")

    ' Respuesta vacía / rota
    vacio = tvFlattenCatalog({})
    tvAssertEqual(vacio.channels.Count(), 0, "respuesta sin `sections` devuelve catálogo vacío")
    nulo = tvFlattenCatalog(invalid)
    tvAssertEqual(nulo.channels.Count(), 0, "respuesta invalid no revienta")

    ' Ocultar adultos (mientras CU-14 siga bloqueado por bcrypt, no se pueden desbloquear)
    sinAdultos = tvFlattenCatalog(fxGetWeb2(), "", true)
    tvAssertInvalid(tvFindChannelByCnId(sinAdultos.channels, 401), "con hideAdult, la sección adulta desaparece")
    tvAssertInvalid(tvFindChannelByCnId(sinAdultos.channels, 502), "con hideAdult, el canal adulto suelto también")
    tvAssertEqual(tvFindChannelByCnId(sinAdultos.channels, 501).cnId, 501, "su vecino no adulto se queda")

    tvSuite("FlattenCatalog — categorías")

    canales = tvChannelsForCategory(r.sections, 0)
    tvAssertEqual(canales.Count(), 2, "canales de la primera categoría")
    tvAssertEqual(tvChannelsForCategory(r.sections, 99).Count(), 0, "categoría inexistente devuelve []")
    tvAssertEqual(tvCategoryIndexForChannel(r.sections, nativa), 0, "índice de categoría del canal activo")
    tvAssertEqual(tvCategoryIndexForChannel(r.sections, invalid), 0, "canal invalid cae a la categoría 0")
end sub
