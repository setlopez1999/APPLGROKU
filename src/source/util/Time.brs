' Utilidades de tiempo. Todo aritmética pura sobre segundos Unix, sin `roDateTime`.
'
' Dos razones:
'  1. Los timestamps del backend son Unix en SEGUNDOS (no milisegundos) — MODELS.md.
'  2. Manteniéndolo puro se puede testear en el PC. El desfase horario del dispositivo entra como
'     PARÁMETRO (`utcOffsetSec`), no se lee aquí dentro: quien llama lo obtiene del Roku y lo pasa.
'     Así el mismo cálculo es reproducible en un test.

' "02:30 PM" — mismo formato que el original (player.js:279-302).
function tvFormatTime12h(unixSec as longinteger, utcOffsetSec = 0 as integer) as string
    if unixSec <= 0 then return ""

    local = unixSec + utcOffsetSec
    secondsOfDay = tvSecondsOfDay(local)
    hours24 = Int(secondsOfDay / 3600)
    minutes = Int((secondsOfDay - hours24 * 3600) / 60)

    ampm = "AM"
    hours = hours24
    if hours >= 12
        ampm = "PM"
        if hours > 12 then hours = hours - 12
    end if
    if hours = 0 then hours = 12      ' medianoche es 12 AM, no 0 AM

    return tvPad2(hours) + ":" + tvPad2(minutes) + " " + ampm
end function

' "14:30" — para la cabecera de horas de la parrilla.
function tvFormatTime24h(unixSec as longinteger, utcOffsetSec = 0 as integer) as string
    if unixSec <= 0 then return ""
    secondsOfDay = tvSecondsOfDay(unixSec + utcOffsetSec)
    hours = Int(secondsOfDay / 3600)
    minutes = Int((secondsOfDay - hours * 3600) / 60)
    return tvPad2(hours) + ":" + tvPad2(minutes)
end function

' Segundos transcurridos desde la medianoche local.
' Ojo: `rem` NO se puede usar como nombre de variable — en BrightScript inicia un comentario.
function tvSecondsOfDay(localSec as longinteger) as integer
    resto = localSec mod 86400
    if resto < 0 then resto = resto + 86400    ' el mod de un negativo da negativo
    return Int(resto)
end function

' Medianoche local del día al que pertenece ese instante, en segundos Unix.
function tvStartOfDay(unixSec as longinteger, utcOffsetSec = 0 as integer) as longinteger
    return unixSec - tvSecondsOfDay(unixSec + utcOffsetSec)
end function

function tvIsSameDay(aSec as longinteger, bSec as longinteger, utcOffsetSec = 0 as integer) as boolean
    return tvStartOfDay(aSec, utcOffsetSec) = tvStartOfDay(bSec, utcOffsetSec)
end function

' Porcentaje 0-100 de un tramo de tiempo ya transcurrido. Fuera de rango devuelve 0 o 100 en vez de
' un número absurdo: alimenta una barra de progreso.
function tvPercentElapsed(startSec as longinteger, endSec as longinteger, nowSec as longinteger) as integer
    if endSec <= startSec then return 0
    if nowSec <= startSec then return 0
    if nowSec >= endSec then return 100
    return Int(((nowSec - startSec) * 100) / (endSec - startSec))
end function

function tvIsWithinRange(startSec as longinteger, endSec as longinteger, nowSec as longinteger) as boolean
    return nowSec >= startSec and nowSec <= endSec
end function

function tvPad2(n as integer) as string
    if n < 10 then return "0" + Str(n).Trim()
    return Str(n).Trim()
end function
