' Catch-up (grabación / DVR de Wowza).
'
' La URL de la grabación NO se recibe del backend: se CONSTRUYE a partir de la del vivo
' (docs/BACKEND-GOTCHAS.md §2). Se escanearon todas las claves de get-web2 y get-epgguide en los dos
' ISP y ningún endpoint devuelve una url de grabación; los únicos campos relacionados son `url` (el
' vivo) y `catchup` (un entero 0/1).
'
'   vivo:       https://host:1936/directorio/canal.stream/playlist.m3u8
'   grabación:  https://host:1936/directorio/canal.stream/playlist_dvr_range-{inicio}-{duración}.m3u8
'
' Consecuencia (la regla más importante): la grabación solo puede existir en el MISMO directorio que
' el vivo. Si ese directorio no graba, no hay catch-up posible para ese canal y la app no puede hacer
' nada al respecto.
'
' Fórmula tomada de la app móvil (app-mobile-v3, player_screen.dart:218).

function tvCatchupUrl(liveUrl as string, startSec as longinteger, durationSec as longinteger) as string
    if liveUrl = "" then return ""
    if durationSec <= 0 then return ""

    base = liveUrl
    idx = Instr(1, liveUrl, ".m3u8")
    if idx > 0 then base = Left(liveUrl, idx - 1)

    return base + "_dvr_range-" + tvNumToStr(startSec) + "-" + tvNumToStr(durationSec) + ".m3u8"
end function

' URL de la grabación de un programa del EPG.
function tvCatchupUrlForProgram(liveUrl as string, program as object) as string
    if program = invalid then return ""
    duration = program.fechaFin - program.fechaIni
    return tvCatchupUrl(liveUrl, program.fechaIni, duration)
end function

' ¿Se puede OFRECER catch-up de este programa?
'
' Ojo con el flag: `catchup` sale de la base de datos del dashboard, lo pone un humano y nadie lo
' valida contra el servidor de vídeo (§3). Hay canales marcados con catchup=1 cuyo directorio
' devuelve 404. Por eso esto es condición NECESARIA pero no suficiente: antes de dibujar el play hay
' que SONDEAR la url y cachear el resultado (el DVR es binario, §4 — una sonda por canal basta).
function tvCatchupIsOffered(isCatchupClient as boolean, channel as object, program as object, nowSec as longinteger) as boolean
    if not isCatchupClient then return false
    if channel = invalid or program = invalid then return false
    if channel.catchup <> 1 then return false
    if channel.streamUrl = "" then return false

    ' Solo programas ya terminados: el actual y los futuros se ven en vivo.
    return program.fechaFin > 0 and program.fechaFin <= nowSec
end function

' Str() de un número sin el espacio inicial que mete BrightScript.
function tvNumToStr(n as longinteger) as string
    return Str(n).Trim()
end function

' ---- CU-15: el salto de avance/retroceso -------------------------------------
'
' UNA DIECISEISAVA PARTE de la duración, no un número fijo de segundos: así el salto es
' proporcionado tanto en una grabación de 20 minutos (75 s) como en una de 3 horas (11 min).
' Un salto fijo de 10 s es inútil en una película y uno de 5 min se pasa de largo en un noticiero.
'
' Se acota por abajo para que en una grabación muy corta el botón haga algo perceptible.
function tvCatchupSeekStepSec(durationSec as integer) as integer
    if durationSec <= 0 then return 10

    paso = Int(durationSec / 16)
    if paso < 10 then return 10
    return paso
end function

' Posición resultante de saltar, acotada a la grabación. Sin acotar, Roku rechaza el `seek` fuera
' de rango y el botón no hace nada.
function tvCatchupSeekTarget(positionSec as integer, stepSec as integer, forward as boolean, durationSec as integer) as integer
    if forward
        destino = positionSec + stepSec
    else
        destino = positionSec - stepSec
    end if

    if destino < 0 then return 0
    if durationSec > 0 and destino > durationSec then return durationSec
    return destino
end function
