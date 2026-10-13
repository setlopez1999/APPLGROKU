' Resistencia del streaming: la cadena completa de recuperación ante caídas.
'
' Los otros tests comprueban cada regla por separado. Este recorre SECUENCIAS de estados del
' reproductor, que es como se cae un canal en la vida real: no con un error limpio, sino con una
' sucesión de baches, atascos y arranques fallidos.
'
' La propiedad que se verifica es siempre la misma: **el canal nunca se queda muerto**. Mientras
' haya una url, siempre hay una acción de recuperación pendiente.

sub testStreaming()
    tvSuite("Streaming — un canal con url SIEMPRE tiene salida")

    url = "https://h:1936/c/playlist.m3u8"

    ' Recorrido de una caída típica: reproduce, bache, atasco, error, y vuelta.
    secuencia = ["playing", "buffering", "buffering", "buffering", "error", "buffering", "playing"]
    fueraDePlaying = 0
    recuperaciones = 0
    muerto = 0

    for each estado in secuencia
        if estado = "playing"
            fueraDePlaying = 0
        else
            fueraDePlaying = fueraDePlaying + 1
        end if

        hayAccion = false
        if estado = "error" and tvShouldRetryPlayback(url, 99) then hayAccion = true
        if tvShouldRecoverFromStall(estado, fueraDePlaying, false)
            hayAccion = true
            recuperaciones = recuperaciones + 1
        end if

        ' Un estado que no es "playing" y para el que NADIE tiene una acción es un canal muerto.
        if estado <> "playing" and not hayAccion and fueraDePlaying >= tvStallTimeoutSec() then muerto = muerto + 1
    end for

    tvAssertEqual(muerto, 0, "en ninguna fase el canal se queda sin acción de recuperación")

    tvSuite("Streaming — el error SIEMPRE reintenta, pase el tiempo que pase")

    ' Con tope, al agotarlo el canal se queda negro para siempre y hay que reiniciarlo a mano.
    sinSalida = 0
    for intento = 0 to 500
        if not tvShouldRetryPlayback(url, intento) then sinSalida = sinSalida + 1
    end for
    tvAssertEqual(sinSalida, 0, "500 intentos seguidos y sigue reintentando")

    tvSuite("Streaming — el atasco mudo se recupera, el bache corto no se toca")

    ' El atasco no da error: hay que contarlo. Pero recargar encima de un bache que iba a
    ' resolverse solo alarga el corte en vez de arreglarlo.
    recuperaAntesDeTiempo = 0
    for s = 0 to tvStallTimeoutSec() - 1
        if tvShouldRecoverFromStall("buffering", s, false) then recuperaAntesDeTiempo = recuperaAntesDeTiempo + 1
    end for
    tvAssertEqual(recuperaAntesDeTiempo, 0, "antes del umbral no se toca el reproductor")
    tvAssertEqual(tvShouldRecoverFromStall("buffering", tvStallTimeoutSec(), false), true, "en el umbral sí")

    ' Y la contraparte: mientras el búfer SE LLENE, no se recarga aunque se pase del umbral. Es lo
    ' que convertía cada bache en una pantalla negra (medido en el aparato el 2026-10-13).
    recargaLlenando = 0
    for s = 0 to 600
        if tvShouldRecoverFromStall("buffering", s, true) then recargaLlenando = recargaLlenando + 1
    end for
    tvAssertEqual(recargaLlenando, 0, "mientras el búfer se llena NUNCA se recarga")

    ' Y reproduciendo no se recarga nunca: sería el peor fallo posible aquí.
    recargaReproduciendo = 0
    for s = 0 to 600
        if tvShouldRecoverFromStall("playing", s, false) then recargaReproduciendo = recargaReproduciendo + 1
    end for
    tvAssertEqual(recargaReproduciendo, 0, "un canal que va bien NUNCA se recarga")

    tvSuite("Streaming — la url vacía no entra nunca al reproductor")

    ' EL CASO DE LA PANTALLA NEGRA PERMANENTE: con reintento automático, una url vacía se
    ' reintenta para siempre sin recuperarse jamás (BACKEND-GOTCHAS §5).
    tvAssertEqual(tvShouldRetryPlayback("", 0), false, "no se reintenta una url vacía")
    tvAssertEqual(tvResolveStreamLoad("", "", "none"), "none", "no se carga una url vacía")
    tvAssertEqual(tvResolveStreamLoad(url, "", "playing"), "none", "ni se sustituye lo que suena por nada")

    tvSuite("Streaming — no se recarga lo que ya está sonando")

    ' Sin esta regla, cada redibujado de la pantalla reinicia el vídeo y la imagen parpadea.
    parpadeos = 0
    for i = 1 to 50
        if tvResolveStreamLoad(url, url, "playing") <> "none" then parpadeos = parpadeos + 1
    end for
    tvAssertEqual(parpadeos, 0, "50 redibujados y ni una recarga")

    ' Pero tras DETENER (abrir una grabación) hay que volver a preparar: "reanudar" no hace nada
    ' sobre un reproductor detenido y el canal se quedaría negro al volver.
    tvAssertEqual(tvResolveStreamLoad(url, url, "stopped"), "resume", "tras detener, se vuelve a preparar")

    tvSuite("Streaming — el User-Agent obligatorio")

    ' Algunos servidores entregan el flujo SOLO si empieza por APPMOVIL; al resto le responden 403,
    ' y en pantalla eso es negro sin mensaje, idéntico a un canal caído (05-REPRODUCCION).
    ua = tvStreamUserAgent()
    tvAssertEqual(Left(ua, 8), "APPMOVIL", "el User-Agent empieza por APPMOVIL")
    tvAssert(Len(ua) > 8, "y lleva el identificador del cliente detrás")

    tvSuite("Streaming — el reporte al operador no puede tumbar la reproducción")

    r = tvFlattenCatalog(fxGetWeb2())
    canal = tvFindChannelByCnId(r.channels, 101)

    ' Es un dato para el panel del operador, no el servicio que el usuario consume: si falla, se
    ' ignora. Y no se manda a ciegas sin red, que solo acumula fallos.
    tvAssertEqual(tvShouldSendHeartbeat(true, true, false, canal, "tok"), true, "reproduciendo y con red: se manda")
    tvAssertEqual(tvShouldSendHeartbeat(true, false, false, canal, "tok"), false, "sin red NO se manda a ciegas")
    tvAssertEqual(tvShouldSendHeartbeat(false, true, false, canal, "tok"), false, "si no reproduce, no hay nada que reportar")
end sub
