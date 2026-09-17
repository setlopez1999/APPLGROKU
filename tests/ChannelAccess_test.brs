sub testChannelAccess()
    tvSuite("domain/usecase/ChannelAccess — premium (CU-15) y primer canal (CU-05)")

    r = tvFlattenCatalog(fxGetWeb2())
    conPack = [30]
    sinPack = []

    tvAssertEqual(tvPremiumAllowed(r.sections, 10, sinPack), true, "sección no premium se permite sin plan")
    tvAssertEqual(tvPremiumAllowed(r.sections, 30, conPack), true, "sección premium con el pack contratado")
    tvAssertEqual(tvPremiumAllowed(r.sections, 30, sinPack), false, "sección premium sin el pack se bloquea")
    tvAssertEqual(tvPremiumAllowed(r.sections, 999, conPack), false, "sección desconocida se bloquea (igual que el original)")
    tvAssertEqual(tvPremiumAllowed(r.sections, 10, invalid), true, "premiumsallowed invalid no revienta")

    ' Primer canal: ni premium bloqueado ni adulto
    primero = tvGetFirstAllowedChannel(r.channels, r.sections, sinPack)
    tvAssertEqual(primero.cnId, 101, "arranca en el primer canal permitido")

    ' Si TODO está bloqueado, cae al primero igual que el original en vez de dejar pantalla negra
    soloAdultos = []
    for each c in r.channels
        if c.esAdulto then soloAdultos.Push(c)
    end for
    fallback = tvGetFirstAllowedChannel(soloAdultos, r.sections, sinPack)
    tvAssertEqual(fallback.cnId, soloAdultos[0].cnId, "sin ninguno permitido cae al primero (fallback del original)")

    ' Lista vacía: el llamador decide, no se inventa un canal
    tvAssertInvalid(tvGetFirstAllowedChannel([], r.sections, sinPack), "lista vacía devuelve invalid")
    tvAssertInvalid(tvGetFirstAllowedChannel(invalid, r.sections, sinPack), "lista invalid devuelve invalid")

    tvAssertEqual(tvFindChannelByCnId(r.channels, 101).nombre, "Nativa", "busca canal por cn_id")
    tvAssertInvalid(tvFindChannelByCnId(r.channels, 9999), "cn_id inexistente devuelve invalid")
end sub
