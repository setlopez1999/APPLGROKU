sub testZapping()
    tvSuite("domain/usecase/Zapping — CU-11 (sin la recursión del original)")

    r = tvFlattenCatalog(fxGetWeb2())
    sinPack = []
    conPack = [30]

    ' Orden de canales con url: 101, 102 (Nacionales) · 301 (Premium) · 401 (Adulto) · 501, 502 (Mixta)
    siguiente = tvFindNextChannel(r.channels, 101, true, r.sections, conPack)
    tvAssertEqual(siguiente.cnId, 102, "abajo va al siguiente canal")

    anterior = tvFindNextChannel(r.channels, 102, false, r.sections, conPack)
    tvAssertEqual(anterior.cnId, 101, "arriba va al anterior")

    ' Salta lo que no se puede ver: premium sin pack y adultos
    saltando = tvFindNextChannel(r.channels, 102, true, r.sections, sinPack)
    tvAssertEqual(saltando.cnId, 501, "salta el premium bloqueado y el adulto")

    conPremium = tvFindNextChannel(r.channels, 102, true, r.sections, conPack)
    tvAssertEqual(conPremium.cnId, 301, "con el pack contratado sí entra al premium")

    ' Vuelta en los dos extremos
    ultimo = r.channels[r.channels.Count() - 1]
    vuelta = tvFindNextChannel(r.channels, ultimo.cnId, true, r.sections, conPack)
    tvAssertEqual(vuelta.cnId, 101, "del último hacia abajo vuelve al primero")
    vueltaArriba = tvFindNextChannel(r.channels, 101, false, r.sections, conPack)
    tvAssertEqual(vueltaArriba.cnId, 501, "del primero hacia arriba vuelve al último permitido")

    ' EL TEST CRÍTICO: el original entra en recursión infinita aquí (player.js:647-685)
    soloBloqueados = []
    for each c in r.channels
        if c.esAdulto then soloBloqueados.Push(c)
    end for
    tvAssertInvalid(tvFindNextChannel(soloBloqueados, soloBloqueados[0].cnId, true, r.sections, sinPack), "todos bloqueados: devuelve invalid, NO desborda la pila")
    tvAssertInvalid(tvFindNextChannel(soloBloqueados, soloBloqueados[0].cnId, false, r.sections, sinPack), "lo mismo hacia arriba")

    ' Bordes
    tvAssertInvalid(tvFindNextChannel([], 101, true, r.sections, conPack), "lista vacía devuelve invalid")
    tvAssertInvalid(tvFindNextChannel(invalid, 101, true, r.sections, conPack), "lista invalid devuelve invalid")

    uno = [r.channels[0]]
    solo = tvFindNextChannel(uno, uno[0].cnId, true, r.sections, conPack)
    tvAssertEqual(solo.cnId, uno[0].cnId, "con un solo canal se queda en él")

    ' El backend quitó el canal que estaba sonando (§6: los canales aparecen y desaparecen)
    huerfano = tvFindNextChannel(r.channels, 9999, true, r.sections, conPack)
    tvAssertEqual(huerfano.cnId, 102, "si el canal actual ya no existe, sigue desde el principio")

    tvAssertEqual(tvIndexOfChannel(r.channels, 301), 2, "índice del canal en la lista")
    tvAssertEqual(tvIndexOfChannel(r.channels, 9999), -1, "canal ausente devuelve -1")
end sub
