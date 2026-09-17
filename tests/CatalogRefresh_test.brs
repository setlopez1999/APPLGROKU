sub testCatalogRefresh()
    tvSuite("domain/usecase/CatalogRefresh — CU-17 (BACKEND-GOTCHAS §6)")

    r = tvFlattenCatalog(fxGetWeb2())
    conPack = [30]
    sinPack = []
    activo = tvFindChannelByCnId(r.channels, 101)

    ' Regla 1: sin cambios reales NO se reconstruye (si no, se corta el vídeo y se mueve el foco
    ' cada 60 segundos mientras el usuario navega).
    firma = tvCatalogSignature(r.channels)
    igual = tvFlattenCatalog(fxGetWeb2())
    tvAssertEqual(tvCatalogChanged(firma, igual.channels), false, "misma respuesta: no hay cambio")

    conCdn = tvFlattenCatalog(fxGetWeb2(), "https://cdn.isp.tv/live/")
    tvAssertEqual(tvCatalogChanged(firma, conCdn.channels), true, "si cambian las urls sí hay cambio")
    tvAssertEqual(tvCatalogChanged("", r.channels), true, "sin firma previa siempre hay cambio")
    tvAssertEqual(tvCatalogSignature(invalid), "", "catálogo invalid no revienta")

    tvSuite("CatalogRefresh — qué hacer con el canal que está sonando")

    ' Todo igual: no se toca nada
    keep = tvResolveAfterRefresh(activo, activo.streamUrl, r.channels, r.sections, conPack)
    tvAssertEqual(keep.action, "keep", "sin cambios se deja la reproducción en paz")

    ' Le cambiaron la url al canal (pasa al activarse multi-CDN o al mover el stream de servidor)
    reload = tvResolveAfterRefresh(activo, "https://vieja/playlist.m3u8", r.channels, r.sections, conPack)
    tvAssertEqual(reload.action, "reload", "si la url cambió hay que recargar")
    tvAssertEqual(reload.channel.cnId, 101, "y se recarga el mismo canal")

    ' Se perdió el acceso premium a mitad de sesión
    premium = tvFindChannelByCnId(r.channels, 301)
    blocked = tvResolveAfterRefresh(premium, premium.streamUrl, r.channels, r.sections, sinPack)
    tvAssertEqual(blocked.action, "blocked", "si se pierde el premium se bloquea, no se recarga")

    ' El permiso manda sobre la url: aunque además haya cambiado la url, primero se bloquea
    ambos = tvResolveAfterRefresh(premium, "https://vieja/x.m3u8", r.channels, r.sections, sinPack)
    tvAssertEqual(ambos.action, "blocked", "permiso perdido y url nueva: gana el bloqueo")

    ' El backend quitó el canal
    fantasma = { cnId: 9999, streamUrl: "x", sectionId: 10, esAdulto: false }
    quitado = tvResolveAfterRefresh(fantasma, "x", r.channels, r.sections, conPack)
    tvAssertEqual(quitado.action, "switch", "canal desaparecido: se salta al primero permitido")
    tvAssertEqual(quitado.channel.cnId, 101, "y ese es el primer permitido")

    ' Catálogo vacío: sesión degradada, el llamador reintenta
    vacio = tvResolveAfterRefresh(activo, activo.streamUrl, [], r.sections, conPack)
    tvAssertEqual(vacio.action, "none", "sin canales no se inventa nada")

    sinActivo = tvResolveAfterRefresh(invalid, "", r.channels, r.sections, conPack)
    tvAssertEqual(sinActivo.action, "switch", "sin canal activo se elige el primero permitido")

    tvSuite("CatalogRefresh — ritmo adaptativo y reintento de la guía")

    tvAssertEqual(tvRefreshIntervalSec(true, true), 60, "todo bien: refresco normal de 60 s")
    tvAssertEqual(tvRefreshIntervalSec(false, true), 15, "sin canal reproducible: reintenta antes")
    tvAssertEqual(tvRefreshIntervalSec(true, false), 15, "sin guía: reintenta antes")

    ' §7: la guía se reintenta por su cuenta aunque los canales no hayan cambiado
    tvAssertEqual(tvShouldRetryGuide(true, false), true, "guía vacía se reintenta aunque nada cambie")
    tvAssertEqual(tvShouldRetryGuide(false, true), true, "si cambió el catálogo, también")
    tvAssertEqual(tvShouldRetryGuide(false, false), false, "guía llena y sin cambios: no se pide")
end sub
