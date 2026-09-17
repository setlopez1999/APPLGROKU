sub testPlayback()
    tvSuite("domain/usecase/Playback — CU-16 heartbeat")

    r = tvFlattenCatalog(fxGetWeb2())
    canal = tvFindChannelByCnId(r.channels, 101)

    tvAssertEqual(tvHeartbeatIntervalSec(), 15, "el heartbeat va cada 15 segundos")
    tvAssertEqual(tvShouldSendHeartbeat(true, true, false, canal, "tok"), true, "reproduciendo y con conexión: se manda")
    tvAssertEqual(tvShouldSendHeartbeat(false, true, false, canal, "tok"), false, "si no está reproduciendo, no")
    tvAssertEqual(tvShouldSendHeartbeat(true, false, false, canal, "tok"), false, "sin conexión, no")
    tvAssertEqual(tvShouldSendHeartbeat(true, true, true, canal, "tok"), false, "con el modal de restricción abierto se detiene")
    tvAssertEqual(tvShouldSendHeartbeat(true, true, false, invalid, "tok"), false, "sin canal activo, no")
    tvAssertEqual(tvShouldSendHeartbeat(true, true, false, canal, ""), false, "sin token, no")

    tvSuite("Playback — CU-18 conectividad")

    tvAssertEqual(tvShouldShowOfflineModal(false, false), true, "sin conexión se muestra el modal")
    tvAssertEqual(tvShouldShowOfflineModal(true, false), false, "con conexión no")

    ' Sin este guard, cada comprobación fallida relanzaría el modal y robaría el foco
    tvAssertEqual(tvShouldShowOfflineModal(false, true), false, "si ya está abierto no se vuelve a abrir")

    ' El bug del original: el mensaje se programaba SIEMPRE, incluso tras reconectar bien
    reconectado = tvReconnectAction(true, true, canal)
    tvAssertEqual(reconectado.action, "relaunch", "con conexión y canal previo se reanuda")
    tvAssertEqual(reconectado.message, "", "y NO se muestra el mensaje de error (bug del original)")

    sinCatalogo = tvReconnectAction(true, false, invalid)
    tvAssertEqual(sinCatalogo.action, "reload", "con conexión pero sin catálogo se recarga la sesión")

    sigueCaido = tvReconnectAction(false, true, canal)
    tvAssertEqual(sigueCaido.action, "retry", "sin conexión se sigue reintentando")
    tvAssert(sigueCaido.message <> "", "y ahí sí se muestra el mensaje")

    tvSuite("Playback — reintento y urls vacías (BACKEND-GOTCHAS §5 y §10)")

    tvAssertEqual(tvPlayerRetryDelayMs(), 2000, "se reintenta a los 2 segundos")
    tvAssertEqual(tvShouldRetryPlayback("https://h/p.m3u8", 0), true, "un stream caído se reintenta")
    tvAssertEqual(tvShouldRetryPlayback("https://h/p.m3u8", 3), false, "pero no infinitamente")

    ' EL CASO DE LA PANTALLA NEGRA PERMANENTE: url vacía + reintento automático
    tvAssertEqual(tvShouldRetryPlayback("", 0), false, "una url VACÍA no se reintenta nunca")

    tvAssertEqual(tvIsPlayable(canal), true, "canal con url es reproducible")
    tvAssertEqual(tvIsPlayable(invalid), false, "canal invalid no lo es")
    tvAssertEqual(tvIsPlayable({ streamUrl: "" }), false, "canal con url vacía tampoco (no es lo mismo que invalid)")

    tvSuite("Playback — orden de validaciones antes de reproducir")

    conPack = [30]
    sinPack = []
    premium = tvFindChannelByCnId(r.channels, 301)
    adulto = tvFindChannelByCnId(r.channels, 401)

    tvAssertEqual(tvResolveLaunchStep(canal, r.sections, conPack, false), "play", "canal normal: vía libre")
    tvAssertEqual(tvResolveLaunchStep(premium, r.sections, sinPack, false), "premium", "sin el pack: modal de venta")
    tvAssertEqual(tvResolveLaunchStep(premium, r.sections, conPack, false), "play", "con el pack: se reproduce")
    tvAssertEqual(tvResolveLaunchStep(adulto, r.sections, conPack, false), "adult", "canal adulto: pide PIN")

    ' Tras validar el PIN una vez, no se vuelve a pedir en toda la sesión
    tvAssertEqual(tvResolveLaunchStep(adulto, r.sections, conPack, true), "play", "con los adultos ya desbloqueados, se reproduce")

    ' El premium se comprueba ANTES que el adulto (player.js:160-169)
    premiumYAdulto = { streamUrl: "https://h/x.m3u8", sectionId: 30, esAdulto: true, restriccion: 0 }
    tvAssertEqual(tvResolveLaunchStep(premiumYAdulto, r.sections, sinPack, false), "premium", "premium se valida antes que adulto")

    ' La IP es la última: es la única que gasta una llamada de red
    conIp = { streamUrl: "https://h/x.m3u8", sectionId: 10, esAdulto: false, restriccion: 1 }
    tvAssertEqual(tvResolveLaunchStep(conIp, r.sections, conPack, false), "ip", "canal con restricción: valida IP")

    tvAssertEqual(tvResolveLaunchStep({ streamUrl: "", sectionId: 10 }, r.sections, conPack, false), "unplayable", "sin url no se intenta nada")
end sub
