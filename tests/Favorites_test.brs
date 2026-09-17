sub testFavorites()
    tvSuite("domain/usecase/Favorites — CU-08 y CU-09")

    r = tvFlattenCatalog(fxGetWeb2())

    ids = tvParseFavoriteIds({ channels: [{ cn_id: 101 }, { cn_id: 501 }] })
    tvAssertEqual(ids.Count(), 2, "se parsean los ids de favoritos")
    tvAssertEqual(tvParseFavoriteIds({}).Count(), 0, "respuesta sin `channels` devuelve []")
    tvAssertEqual(tvParseFavoriteIds(invalid).Count(), 0, "respuesta invalid no revienta")

    tvAssertEqual(tvIsFavorite(ids, 101), true, "canal marcado es favorito")
    tvAssertEqual(tvIsFavorite(ids, 102), false, "canal no marcado no lo es")
    tvAssertEqual(tvIsFavorite(invalid, 101), false, "lista invalid no revienta")

    tvAssertEqual(tvToggleFavoriteAction(ids, 101), "delete", "si ya es favorito, toca quitarlo")
    tvAssertEqual(tvToggleFavoriteAction(ids, 102), "add", "si no lo es, toca añadirlo")

    tvSuite("Favorites — actualización local optimista")

    quitado = tvToggleFavoriteLocal(ids, 101)
    tvAssertEqual(quitado.Count(), 1, "quitar deja uno")
    tvAssertEqual(tvIsFavorite(quitado, 101), false, "y el quitado ya no está")

    anadido = tvToggleFavoriteLocal(ids, 102)
    tvAssertEqual(anadido.Count(), 3, "añadir deja tres")
    tvAssertEqual(tvIsFavorite(anadido, 102), true, "y el nuevo sí está")
    tvAssertEqual(tvIsFavorite(ids, 102), false, "la lista original no se muta")

    desdeVacio = tvToggleFavoriteLocal([], 101)
    tvAssertEqual(desdeVacio.Count(), 1, "se puede añadir el primero desde lista vacía")

    tvSuite("Favorites — cruce con el catálogo vigente")

    lista = tvFavoriteChannels(ids, r.channels)
    tvAssertEqual(lista.Count(), 2, "salen los dos favoritos que existen")
    tvAssertEqual(lista[0].cnId, 101, "en el orden del catálogo, no el de la respuesta")

    ' El favorito que ya no está en el catálogo (salió del plan o lo quitó el ISP) se salta callando
    conFantasma = [101, 9999]
    filtrada = tvFavoriteChannels(conFantasma, r.channels)
    tvAssertEqual(filtrada.Count(), 1, "el favorito que ya no existe no se pinta")
    tvAssertEqual(filtrada[0].cnId, 101, "y el que sí existe se conserva")

    tvAssertEqual(tvFavoriteChannels([], r.channels).Count(), 0, "sin favoritos, lista vacía")
    tvAssertEqual(tvFavoriteChannels(ids, invalid).Count(), 0, "catálogo invalid no revienta")
end sub
