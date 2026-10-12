' Overlay de "TV en directo": los dos modos, la prioridad del ATRAS y la salida del canal.
'
' Spec: docs_final/cu/CU-12-overlay.md, CU-13-franja-canal.md y CU-25-salir.md del rediseno.
'
' Por que esto vive en `domain/` y no en la pantalla: es la pieza que mas facil es implementar mal
' —un error aqui deja al usuario sin poder salir, o lo saca del canal cuando solo queria cerrar un
' panel— y es logica pura, asi que se puede probar entera sin aparato.

' ---- ritmos (02-ARQUITECTURA, "Ritmos y temporizadores") ---------------------

' Auto-ocultado del overlay. Equivale a un ATRAS automatico: el caso habitual en un televisor es
' que el usuario abra la guia, elija un canal y se vaya o se duerma. Sin esto el aparato se queda
' horas con la guia encima del video.
function tvOverlayAutoHideSec() as integer
    return 120
end function

' La franja que aparece al zapear con el overlay oculto.
function tvChannelStripSec() as integer
    return 5
end function

' Ventana del doble ATRAS para cerrar el canal.
function tvExitConfirmWindowMs() as integer
    return 2000
end function

' ---- los dos modos -----------------------------------------------------------

' Con el overlay VISIBLE las flechas mueven el foco; con el overlay OCULTO zapean.
'
' Si zapearan tambien con el overlay visible, cada movimiento del foco por la parrilla cambiaria de
' canal, que es exactamente lo contrario de lo que el usuario quiere al explorar la guia.
function tvShouldZap(overlayVisible as boolean) as boolean
    return not overlayVisible
end function

' Al alternar el modo hay que mover el foco EXPLICITAMENTE. Si no, se queda en un componente que ya
' no esta dibujado y el mando deja de responder por completo (CU-12).
'
'   al mostrar  -> las categorias
'   al ocultar  -> el receptor de teclas de pantalla completa
function tvOverlayFocusTarget(overlayVisible as boolean) as string
    if overlayVisible then return "tabs"
    return "keys"
end function

' ---- el boton ATRAS, en orden ------------------------------------------------
'
' Regla general: ATRAS cierra el nivel MAS INTERNO que este abierto, nunca dos a la vez.
'
' Los niveles de mas interno a mas externo:
'
'   modal abierto (PIN, premium, restriccion, sin conexion)  -> "closeModal"
'   pantalla apilada (Buscar, Mi lista, Perfil, grabacion)   -> "popScreen"
'   overlay visible y el foco en la grilla                   -> "focusTabs"
'   overlay visible y el foco arriba                         -> "hideOverlay"
'   overlay oculto                                           -> "exit"  (lo confirma el doble ATRAS)
'
' Los dos que casi siempre se implementan mal:
'
'  - Con el foco en la grilla, ATRAS SUBE EL FOCO y NO oculta el overlay. El usuario que esta
'    mirando la guia y pulsa ATRAS quiere retroceder un paso, no perderla entera.
'  - Con el overlay oculto, ATRAS NO lo hace reaparecer. Ahi ATRAS significa salir.
function tvResolveBackAction(modalVisible as boolean, stackDepth as integer, overlayVisible as boolean, zone as string) as string
    if modalVisible then return "closeModal"
    if stackDepth > 1 then return "popScreen"

    if overlayVisible
        if zone = "grid" then return "focusTabs"
        return "hideOverlay"
    end if

    return "exit"
end function

' ---- CU-25: salir del canal con doble ATRAS ----------------------------------
'
' La confirmacion es por doble pulsacion y NO por un dialogo con botones: un dialogo obliga a mover
' el foco hasta "Si" y aceptar, o sea tres pulsaciones para algo que deberia ser inmediato.
'
' `lastBackMs = 0` significa que no hay ninguna pulsacion previa pendiente.
function tvShouldExitOnBack(nowMs as longinteger, lastBackMs as longinteger) as boolean
    if lastBackMs <= 0 then return false

    ' La ventana se mide desde la PRIMERA pulsacion: dos ATRAS separados diez segundos no cierran
    ' nada, el contador ya volvio a empezar.
    return (nowMs - lastBackMs) <= tvExitConfirmWindowMs()
end function

function tvExitHintText() as string
    return "Presiona atrás de nuevo para salir"
end function

' ---- CU-09: cuando hay que recargar el reproductor ---------------------------
'
' Sin esta regla, cada redibujado de la pantalla provoca una recarga y el video parpadea
' constantemente (05-REPRODUCCION, "Regla de carga").
'
'   "none"    es la misma url y el reproductor esta activo  -> no tocar nada
'   "resume"  es la misma url pero fue DETENIDO             -> volver a preparar y reproducir
'   "load"    es otra url                                   -> cargarla y reproducir
'
' La rama "resume" no es un adorno: tras una detencion, un simple "reanudar" no hace nada sobre un
' reproductor detenido y el canal se quedaria negro al volver de una grabacion.
function tvResolveStreamLoad(currentUrl as string, newUrl as string, playerState as string) as string
    if newUrl = "" then return "none"
    if currentUrl <> newUrl then return "load"

    if playerState = "playing" or playerState = "buffering" then return "none"
    return "resume"
end function

' ---- CU-12: ¿se puede auto-ocultar la guía? ----------------------------------
'
' El auto-ocultado existe para destapar el VÍDEO cuando el usuario se fue. Si no hay vídeo que
' destapar, ocultar la guía solo deja un negro mudo: el usuario que vuelve no sabe si la app se
' colgó, si se quedó sin internet o si apagó algo sin querer.
'
' Regla: la cuenta de los 2 minutos sigue corriendo, pero solo oculta si el reproductor está
' realmente en marcha. Si no, se reintenta en el siguiente ciclo.
'
' Esto NO es paranoia de laboratorio: con el reproductor arrancando (buffering) la guía es la
' única pista que tiene el usuario de que la app está viva.
function tvCanAutoHideOverlay(playerState as string) as boolean
    return playerState = "playing"
end function
