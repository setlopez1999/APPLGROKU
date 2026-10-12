sub testOverlay()
    tvSuite("domain/usecase/Overlay — CU-12 los dos modos")

    tvAssertEqual(tvOverlayAutoHideSec(), 120, "el overlay se oculta solo a los 2 minutos")
    tvAssertEqual(tvChannelStripSec(), 5, "la franja del canal dura 5 segundos")
    tvAssertEqual(tvExitConfirmWindowMs(), 2000, "la ventana del doble atrás es de 2 segundos")

    ' Si las flechas zapearan con el overlay visible, cada movimiento del foco por la parrilla
    ' cambiaría de canal.
    tvAssertEqual(tvShouldZap(false), true, "con el overlay oculto las flechas zapean")
    tvAssertEqual(tvShouldZap(true), false, "con el overlay visible NO zapean: mueven el foco")

    ' Sin mover el foco a mano al alternar, se queda en un nodo que ya no se dibuja y el mando
    ' deja de responder del todo.
    tvAssertEqual(tvOverlayFocusTarget(true), "tabs", "al mostrar el overlay el foco va a las categorías")
    tvAssertEqual(tvOverlayFocusTarget(false), "keys", "al ocultarlo va al receptor de teclas")

    tvSuite("Overlay — CU-12 la prioridad del ATRÁS")

    ' De más interno a más externo. Nunca dos niveles de una vez.
    tvAssertEqual(tvResolveBackAction(true, 3, true, "grid"), "closeModal", "el modal es lo primero")
    tvAssertEqual(tvResolveBackAction(false, 2, true, "grid"), "popScreen", "después, la pantalla apilada")

    ' Los dos casos que suelen implementarse mal:
    tvAssertEqual(tvResolveBackAction(false, 1, true, "grid"), "focusTabs", "en la grilla SUBE el foco y no oculta la guía")
    tvAssertEqual(tvResolveBackAction(false, 1, true, "tabs"), "hideOverlay", "en las categorías sí oculta el overlay")
    tvAssertEqual(tvResolveBackAction(false, 1, false, "keys"), "exit", "con el overlay oculto, ATRÁS significa salir")

    ' Con el overlay oculto ATRÁS NO lo hace reaparecer: ahí está reservado para salir.
    tvAssertEqual(tvResolveBackAction(false, 1, false, "grid"), "exit", "con el overlay oculto no reaparece, sea cual sea la zona")

    ' El modal gana aunque el overlay esté oculto (un aviso puede abrirse sobre el vídeo limpio).
    tvAssertEqual(tvResolveBackAction(true, 1, false, "keys"), "closeModal", "un aviso sobre el vídeo limpio se cierra con ATRÁS")

    ' El display es la zona de arriba del overlay: ATRÁS desde ahí oculta, igual que en categorías.
    tvAssertEqual(tvResolveBackAction(false, 1, true, "display"), "hideOverlay", "desde la info del canal también oculta")

    tvSuite("Overlay — CU-25 salir con doble ATRÁS")

    tvAssertEqual(tvShouldExitOnBack(10000&, 0&), false, "el primer ATRÁS nunca cierra: solo avisa")
    tvAssertEqual(tvShouldExitOnBack(10500&, 10000&), true, "el segundo dentro de la ventana cierra")
    tvAssertEqual(tvShouldExitOnBack(12000&, 10000&), true, "justo en el límite de 2 s todavía cierra")

    ' La ventana se mide desde la PRIMERA pulsación: dos ATRÁS separados no cierran nada.
    tvAssertEqual(tvShouldExitOnBack(15000&, 10000&), false, "separados 5 s NO cierra")
    tvAssert(tvExitHintText() <> "", "hay un texto de aviso para la primera pulsación")

    tvSuite("Overlay — CU-09 cuándo recargar el reproductor")

    ' Sin esta regla cada redibujado recarga el vídeo y la imagen parpadea sin parar.
    tvAssertEqual(tvResolveStreamLoad("http://a/x.m3u8", "http://a/x.m3u8", "playing"), "none", "misma url y reproduciendo: no se toca nada")
    tvAssertEqual(tvResolveStreamLoad("http://a/x.m3u8", "http://a/x.m3u8", "buffering"), "none", "misma url y cargando: tampoco")

    ' Tras una detención, "reanudar" no hace nada: hay que volver a preparar.
    tvAssertEqual(tvResolveStreamLoad("http://a/x.m3u8", "http://a/x.m3u8", "stopped"), "resume", "misma url pero detenido: hay que volver a preparar")
    tvAssertEqual(tvResolveStreamLoad("http://a/x.m3u8", "http://a/x.m3u8", "finished"), "resume", "terminado también se vuelve a preparar")
    tvAssertEqual(tvResolveStreamLoad("http://a/x.m3u8", "http://b/y.m3u8", "playing"), "load", "otra url: se carga")
    tvAssertEqual(tvResolveStreamLoad("", "http://b/y.m3u8", "none"), "load", "sin nada cargado: se carga")

    ' Nunca se manda una url vacía: el reintento se quedaría reintentando el vacío para siempre.
    tvAssertEqual(tvResolveStreamLoad("http://a/x.m3u8", "", "playing"), "none", "una url vacía NO llega al reproductor")

    tvSuite("Overlay — CU-12 el auto-ocultado solo destapa vídeo que existe")

    ' El auto-ocultado existe para destapar el VÍDEO. Si no hay vídeo, ocultar la guía deja un
    ' negro mudo y el usuario no sabe si la app se colgó o se quedó sin internet.
    tvAssertEqual(tvCanAutoHideOverlay("playing"), true, "reproduciendo: se puede ocultar")
    tvAssertEqual(tvCanAutoHideOverlay("buffering"), false, "arrancando todavía: la guía se queda")
    tvAssertEqual(tvCanAutoHideOverlay("error"), false, "con el canal caído, la guía se queda")
    tvAssertEqual(tvCanAutoHideOverlay("stopped"), false, "detenido: la guía se queda")
    tvAssertEqual(tvCanAutoHideOverlay("none"), false, "sin nada cargado: la guía se queda")
    tvAssertEqual(tvCanAutoHideOverlay(""), false, "sin reproductor: la guía se queda")
end sub
