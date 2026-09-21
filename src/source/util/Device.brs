' Lo poco que hay que preguntarle al aparato sobre el tiempo.
'
' Vive aparte y NO en `util/Time.brs` a propósito: Time.brs es aritmética pura y se ejecuta en
' `npm test`; esto necesita `roDateTime` y solo corre en el dispositivo. La frontera entre lo
' testeable y lo que no lo es se mantiene limpia.

function tvNowSeconds() as longinteger
    date = CreateObject("roDateTime")
    return date.AsSeconds()
end function

' Desfase horario del aparato, en segundos (negativo al oeste de Greenwich).
'
' Las funciones de `util/Time.brs` lo reciben como PARÁMETRO justo para que el cálculo sea puro y
' testeable. Olvidarse de pasarlo no da error: simplemente se pintan las horas en UTC, y eso se ve
' como una guía desplazada varias horas. Nos pasó en el reproductor a pantalla completa el
' 2026-09-21: el reloj marcaba las 12:09 y la barra ponía 05:00 PM.
function tvDeviceUtcOffsetSec() as integer
    utc = CreateObject("roDateTime")
    utcSeconds = utc.AsSeconds()

    local = CreateObject("roDateTime")
    local.ToLocalTime()
    return Int(local.AsSeconds() - utcSeconds)
end function
