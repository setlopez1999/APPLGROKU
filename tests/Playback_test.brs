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

    ' SIN TOPE, a propósito: en HLS en vivo los cortes son normales. Con un tope, al agotarlo el
    ' canal se queda negro para siempre y hay que reiniciar el canal entero.
    tvAssertEqual(tvShouldRetryPlayback("https://h/p.m3u8", 3), true, "y se sigue reintentando tras 3 intentos")
    tvAssertEqual(tvShouldRetryPlayback("https://h/p.m3u8", 500), true, "no hay límite de intentos")

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

    tvSuite("Playback — CU-09 el error llega EN RÁFAGA")

    ' El nodo Video no emite "error" una vez: lo emite cientos de veces por segundo mientras el
    ' stream no se pueda abrir. Medido en el Roku Express el 2026-10-13 con un canal cuya url
    ' apuntaba a un equipo inalcanzable: 5.130 eventos en 38 s, unos 170 por segundo.
    url = "https://h:1936/c/playlist.m3u8"
    LIBRE = false
    PENDIENTE = true

    tvAssertEqual(tvShouldStartRetry("error", LIBRE, url), true, "el PRIMER error dispara el reintento")
    tvAssertEqual(tvShouldStartRetry("error", PENDIENTE, url), false, "los de la ráfaga se ignoran: ya hay uno en camino")

    ' Si la ráfaga pasara el guard, todo lo demás (texto de estado, reinicio del temporizador,
    ' log) se ejecutaría 170 veces por segundo EN EL HILO DE RENDER, compitiendo con el vídeo.
    pasan = 0
    for i = 1 to 170
        if tvShouldStartRetry("error", PENDIENTE, url) then pasan = pasan + 1
    end for
    tvAssertEqual(pasan, 0, "170 errores seguidos y ni uno pasa mientras hay reintento pendiente")

    ' Y con el guard libre vuelve a contar: no se queda mudo para siempre.
    tvAssertEqual(tvShouldStartRetry("error", LIBRE, url), true, "liberado el guard, el siguiente error sí cuenta")

    tvAssertEqual(tvShouldStartRetry("playing", LIBRE, url), false, "reproduciendo no se reintenta nada")
    tvAssertEqual(tvShouldStartRetry("buffering", LIBRE, url), false, "un bache no es un error")
    tvAssertEqual(tvShouldStartRetry("error", LIBRE, ""), false, "y una url vacía no se reintenta nunca")

    tvSuite("Playback — CU-09 el atasco mudo (sin errorCode)")

    ' El fallo más común de HLS en vivo NO avisa: el canal se queda en buffering, negro y mudo,
    ' sin código de error. Sin perro guardián no se recupera nunca.
    '
    ' Pero el perro guardián TAMBIÉN puede ser el problema. Medido en el Roku Express el
    ' 2026-10-13: con 10 s y mirando solo el estado se disparó 19 VECES EN 5 MINUTOS sobre un canal
    ' que se recuperaba solo. Cada disparo = pantalla negra, sesión HLS nueva y búfer desde cero.
    tvAssertEqual(tvStallTimeoutSec(), 30, "se da por atascado a los 30 segundos, no a los 10")

    PARADO = false
    LLENANDO = true

    tvAssertEqual(tvShouldRecoverFromStall("buffering", 3, PARADO), false, "un bache corto se deja resolver solo")
    tvAssertEqual(tvShouldRecoverFromStall("buffering", 15, PARADO), false, "15 s tampoco: un rebúfer normal dura eso")
    tvAssertEqual(tvShouldRecoverFromStall("buffering", 30, PARADO), true, "30 s con el búfer plantado ya no es un bache")
    tvAssertEqual(tvShouldRecoverFromStall("stopped", 35, PARADO), true, "parado en seco también cuenta")
    tvAssertEqual(tvShouldRecoverFromStall("finished", 35, PARADO), true, "un directo que 'termina' es un atasco")

    ' LA REGLA QUE FALTABA: mientras el búfer se llena, el reproductor está trabajando y llegará
    ' solo. Recargar ahí tira lo ya descargado y ALARGA el corte.
    tvAssertEqual(tvShouldRecoverFromStall("buffering", 30, LLENANDO), false, "si el búfer avanza no se toca, por mucho que tarde")
    tvAssertEqual(tvShouldRecoverFromStall("buffering", 999, LLENANDO), false, "ni a los 16 minutos, mientras siga llenando")

    ' Reproduciendo no se toca nada: recargar un canal que va bien es el peor bug posible aquí.
    tvAssertEqual(tvShouldRecoverFromStall("playing", 999, PARADO), false, "reproduciendo NUNCA se recarga")

    ' Y que no compitan los dos caminos: el de error ya reintenta a los 2 s, que es más rápido.
    tvAssertEqual(tvShouldRecoverFromStall("error", 60, PARADO), false, "con error manda el reintento de 2 s")

    tvSuite("Playback — ¿el búfer avanza?")

    tvAssertEqual(tvBufferIsProgressing(40, 25), true, "del 25% al 40%: avanza")
    tvAssertEqual(tvBufferIsProgressing(26, 25), true, "un solo punto ya es avanzar")
    tvAssertEqual(tvBufferIsProgressing(25, 25), false, "plantado en el mismo sitio: no avanza")
    tvAssertEqual(tvBufferIsProgressing(10, 60), false, "retroceder tampoco es avanzar")

    ' -1 = el reproductor no está reportando relleno. No saberlo NO es lo mismo que saber que
    ' avanza: si contara como avance y el aparato no reportara nunca, el perro guardián quedaría
    ' desactivado para siempre sin que nadie se enterara.
    tvAssertEqual(tvBufferIsProgressing(-1, 25), false, "sin dato no se puede afirmar que avance")
    tvAssertEqual(tvBufferIsProgressing(40, -1), false, "ni con el dato anterior ausente")
    tvAssertEqual(tvBufferIsProgressing(-1, -1), false, "ni sin ninguno de los dos")

end sub
