sub testSearch()
    tvSuite("domain/usecase/Search — normalización")

    tvAssertEqual(tvNormalizeForSearch("Latina"), "latina", "pasa a minúsculas")
    tvAssertEqual(tvNormalizeForSearch("América TV"), "america tv", "quita los acentos")
    tvAssertEqual(tvNormalizeForSearch("Español Ñ"), "espanol n", "también la eñe")
    tvAssertEqual(tvNormalizeForSearch(""), "", "cadena vacía")

    tvSuite("Search — buscar por nombre")

    r = tvFlattenCatalog(fxGetWeb2())

    porNombre = tvSearchChannels(r.channels, "nativa")
    tvAssertEqual(porNombre.Count(), 1, "encuentra por nombre completo")
    tvAssertEqual(porNombre[0].cnId, 101, "y es el canal correcto")

    ' Buscar en cualquier posición: con un teclado de TV nadie escribe el nombre entero
    parcial = tvSearchChannels(r.channels, "tin")
    tvAssertEqual(parcial.Count(), 1, "encuentra por un trozo del nombre (La-tin-a)")

    tvAssertEqual(tvSearchChannels(r.channels, "LATINA").Count(), 1, "no distingue mayúsculas")
    tvAssertEqual(tvSearchChannels(r.channels, "zzzz").Count(), 0, "sin coincidencias devuelve lista vacía")

    tvSuite("Search — buscar por número")

    porNumero = tvSearchChannels(r.channels, "2")
    tvAssert(porNumero.Count() >= 1, "el número encuentra su canal")

    ' Por CUALQUIER PARTE del número: los canales reproducibles de la fixture son el 1, el 2, el
    ' 30, el 60 y el 90. Ninguno es "0", así que con coincidencia exacta esto daría cero.
    porCero = tvSearchChannels(r.channels, "0")
    tvAssertEqual(porCero.Count(), 3, "buscar 0 trae el 30, el 60 y el 90")

    encontroTreinta = false
    for each c in porCero
        if c.numero = 30 then encontroTreinta = true
    end for
    tvAssert(encontroTreinta, "el 30 aparece al buscar 0")

    ' Un número que no existe en ninguna posición no devuelve nada.
    tvAssertEqual(tvSearchChannels(r.channels, "777").Count(), 0, "un número inexistente no trae nada")

    tvSuite("Search — bordes")

    ' Consulta vacía NO devuelve el catálogo entero: parecería que ya se buscó algo
    tvAssertEqual(tvSearchChannels(r.channels, "").Count(), 0, "consulta vacía no devuelve nada")
    tvAssertEqual(tvSearchChannels(r.channels, "   ").Count(), 0, "solo espacios tampoco")
    tvAssertEqual(tvSearchChannels(invalid, "nativa").Count(), 0, "catálogo invalid no revienta")
    tvAssertEqual(tvSearchChannels([], "nativa").Count(), 0, "catálogo vacío devuelve vacío")
    tvAssertEqual(tvChannelMatches(invalid, "x"), false, "canal invalid no revienta")

    ' El orden es el del catálogo, no el de relevancia: en una parrilla de TV el número manda
    varios = tvSearchChannels(r.channels, "a")
    tvAssert(varios.Count() > 1, "una letra común encuentra varios")
    tvAssert(varios[0].numero < varios[varios.Count() - 1].numero, "y salen en el orden del catálogo")
end sub
