sub testDeepLink()
    tvSuite("domain/usecase/DeepLink — el enlace que SÍ abre un canal")

    ok = tvParseDeepLink({ contentId: "2041", mediaType: "livefeed" })
    tvAssertEqual(ok.valid, true, "contentId numérico y tipo livefeed: se abre")
    tvAssertEqual(ok.cnId, 2041, "el contentId ES el cn_id")
    tvAssertEqual(ok.reason, "ok", "y el motivo lo dice")

    ' Roku documenta `contentId`, pero lo que llega es LITERALMENTE lo que venga en la URL, y sus
    ' propias herramientas de prueba mandan otras mayúsculas. Un enlace que no abre por una letra
    ' es un suspenso de certificación que cuesta días encontrar.
    tvAssertEqual(tvParseDeepLink({ contentid: "2041", mediatype: "livefeed" }).cnId, 2041, "todo en minúsculas también")
    tvAssertEqual(tvParseDeepLink({ CONTENTID: "2041", MEDIATYPE: "LIVEFEED" }).cnId, 2041, "todo en mayúsculas también")
    tvAssertEqual(tvParseDeepLink({ ContentID: "2041", MediaType: "LiveFeed" }).valid, true, "y mezclado")

    ' El id puede llegar ya como número si lo pone otra capa en vez de la URL.
    tvAssertEqual(tvParseDeepLink({ contentId: 2041, mediaType: "livefeed" }).cnId, 2041, "un entero vale igual que su texto")

    ' Espacios: una url copiada a mano trae un "%20" que acaba en espacio.
    tvAssertEqual(tvParseDeepLink({ contentId: " 2041 ", mediaType: " livefeed " }).cnId, 2041, "se recortan los espacios")

    tvSuite("DeepLink — qué tipos de contenido acepta una app de TV en directo")

    tvAssertEqual(tvIsSupportedMediaType("livefeed"), true, "livefeed es el tipo de Roku para TV en vivo")
    tvAssertEqual(tvIsSupportedMediaType("live"), true, "live, el nombre antiguo, se sigue aceptando")
    tvAssertEqual(tvIsSupportedMediaType("LiveFeed"), true, "sin distinguir mayúsculas")

    ' Un tipo vacío SE ACEPTA: rechazarlo sería negarse a abrir un canal que existe y que el
    ' usuario pidió, solo porque quien construyó el enlace se dejó un campo.
    tvAssertEqual(tvIsSupportedMediaType(""), true, "sin tipo, pero con id, se abre igual")

    ' Esto no: el enlace dice claramente que apunta a otra cosa.
    tvAssertEqual(tvIsSupportedMediaType("movie"), false, "una película no existe en esta app")
    tvAssertEqual(tvIsSupportedMediaType("episode"), false, "un episodio tampoco")
    tvAssertEqual(tvIsSupportedMediaType("series"), false, "ni una serie")

    pelicula = tvParseDeepLink({ contentId: "2041", mediaType: "movie" })
    tvAssertEqual(pelicula.valid, false, "un enlace a película no abre ningún canal")
    tvAssertEqual(pelicula.reason, "badType", "y se distingue del resto de fallos")

    tvSuite("DeepLink — ARRANQUE NORMAL: no todo lo que no es un enlace es un error")

    ' Esto es el 99% de los arranques: el usuario abre la app desde el menú del Roku. Si esto
    ' contara como enlace roto, cada arranque normal enseñaría un aviso de error.
    normal = tvParseDeepLink(invalid)
    tvAssertEqual(normal.valid, false, "sin argumentos no hay enlace")
    tvAssertEqual(normal.reason, "none", "pero NO es un error: es el arranque de siempre")

    tvAssertEqual(tvParseDeepLink({}).reason, "none", "argumentos vacíos: arranque normal")

    ' Roku añade sus propios argumentos al lanzar (origen, instante…). Ninguno es un contentId.
    tvAssertEqual(tvParseDeepLink({ lastExitOrigin: "poweron", source: "home" }).reason, "none", "los argumentos propios de Roku no son un enlace")

    tvSuite("DeepLink — basura: NUNCA debe dejar la app en blanco")

    ' Esto es lo que prueba el revisor de Roku a propósito, y es lo único que de verdad se
    ' suspende: un enlace inválido tiene que llevar a la app normal, sin cerrarse ni colgarse.
    casos = [
        { id: "abc",          nota: "texto puro" }
        { id: "12abc",        nota: "empieza por número y sigue con letras" }
        { id: "20 41",        nota: "un espacio en medio" }
        { id: "-2041",        nota: "negativo" }
        { id: "0",            nota: "cero: ningún canal tiene cn_id 0" }
        { id: "2041.5",       nota: "decimal" }
        { id: "'; DROP--",    nota: "inyección" }
        { id: "99999999999",  nota: "más largo de lo que cabe en un entero" }
    ]

    for each caso in casos
        resultado = tvParseDeepLink({ contentId: caso.id, mediaType: "livefeed" })
        tvAssertEqual(resultado.valid, false, "no se abre nada con " + caso.nota)
        tvAssertEqual(resultado.cnId, 0, "y el id queda en 0 con " + caso.nota)
    end for

    ' "12abc" es EL caso del parseo perezoso: `Val()` devuelve 12 sin quejarse, así que un enlace a
    ' medio escribir abriría el canal 12, que no es el que nadie pidió.
    tvAssertEqual(tvDeepLinkIdFromString("12abc"), 0, "un id a medias NO se convierte en el canal 12")
    tvAssertEqual(tvDeepLinkIdFromString("2041"), 2041, "un id entero sí")
    tvAssertEqual(tvDeepLinkIdFromString(""), 0, "vacío no")

    ' El desbordamiento silencioso: sin el tope, un id larguísimo da un entero NEGATIVO que encima
    ' podría coincidir con algo.
    tvAssertEqual(tvDeepLinkIdFromString("999999999"), 999999999, "nueve dígitos todavía caben")
    tvAssertEqual(tvDeepLinkIdFromString("1234567890"), 0, "diez ya no: se rechaza antes de desbordar")

    tvSuite("DeepLink — resolver el canal contra el catálogo real")

    r = tvFlattenCatalog(fxGetWeb2())

    enlace = tvParseDeepLink({ contentId: "101", mediaType: "livefeed" })
    canal = tvFindChannelByCnId(r.channels, enlace.cnId)
    tvAssert(canal <> invalid, "el enlace encuentra el canal en el catálogo")
    tvAssertEqual(canal.nombre, "Nativa", "y es el que toca")

    ' Un canal que existió y lo quitaron del plan: el enlace guardado en el Roku sigue apuntando
    ' ahí para siempre. Tiene que avisar, no quedarse mudo.
    fantasma = tvParseDeepLink({ contentId: "999999", mediaType: "livefeed" })
    tvAssertEqual(fantasma.valid, true, "el enlace está bien formado")
    tvAssert(tvFindChannelByCnId(r.channels, fantasma.cnId) = invalid, "pero el canal ya no está en el catálogo")
    tvAssert(tvDeepLinkNotFoundText() <> "", "y hay un aviso que enseñar")

    tvSuite("DeepLink — los controles de acceso NO se saltan")

    ' El riesgo real de un enlace profundo: ser el atajo que se salta el premium y el PIN. Un
    ' enlace a un canal de pago o de adultos tiene que pasar por la MISMA puerta que la parrilla.
    sinPack = []
    premium = tvFindChannelByCnId(r.channels, tvParseDeepLink({ contentId: "301", mediaType: "livefeed" }).cnId)
    adulto = tvFindChannelByCnId(r.channels, tvParseDeepLink({ contentId: "401", mediaType: "livefeed" }).cnId)

    tvAssertEqual(tvResolveLaunchStep(premium, r.sections, sinPack, false), "premium", "un enlace a un canal de pago sigue pidiendo el pack")
    tvAssertEqual(tvResolveLaunchStep(adulto, r.sections, [30], false), "adult", "un enlace a un canal adulto sigue pidiendo el PIN")
    tvAssertEqual(tvResolveLaunchStep(canal, r.sections, sinPack, false), "play", "y uno normal entra directo")
end sub
