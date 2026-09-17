' Construcción de las URLs de la API. Puro texto: aquí no se hace red (eso vive en components/tasks).
'
' Contrato heredado y verificado (docs/BACKEND-GOTCHAS.md §11 y §12) — ojo con estas rarezas:
'  - TODOS son POST, pero los parámetros van en el QUERY STRING, no en el body.
'  - `delete-favorite` es POST, no DELETE.
'  - `desvincular` no lleva body: el token va como query param.
'  - El backend exige el password EN CADA get-web2, no solo en el login.
'  - El heartbeat no es un endpoint normal: es {baseUrl}{token}/{cn_id}.json

function tvApiGetWeb2Url(baseUrl as string, email as string, password as string, deviceId as string, platform as integer, token = "" as string) as string
    url = tvJoinUrl(baseUrl, "api/get-web2")
    url = url + "?user=" + tvUrlEncode(email)
    url = url + "&pass=" + tvUrlEncode(password)
    url = url + "&devid=" + tvUrlEncode(deviceId)
    url = url + "&platform=" + Str(platform).Trim()
    ' El token solo viaja en la revalidación (CU-17), no en el login inicial (CU-01).
    if token <> "" then url = url + "&token=" + tvUrlEncode(token)
    return url
end function

function tvApiEpgGuideUrl(baseUrl as string, email as string) as string
    return tvJoinUrl(baseUrl, "api/get-epgguide") + "?user=" + tvUrlEncode(email)
end function

function tvApiGetFavoritesUrl(baseUrl as string, email as string) as string
    return tvJoinUrl(baseUrl, "api/get-favorite") + "?user_email=" + tvUrlEncode(email)
end function

function tvApiAddFavoriteUrl(baseUrl as string, email as string, cnId as integer) as string
    return tvJoinUrl(baseUrl, "api/set-favorite") + "?user_email=" + tvUrlEncode(email) + "&channel_id=" + Str(cnId).Trim()
end function

' POST, no DELETE (verificado en player.js:875).
function tvApiDeleteFavoriteUrl(baseUrl as string, email as string, cnId as integer) as string
    return tvJoinUrl(baseUrl, "api/delete-favorite") + "?user_email=" + tvUrlEncode(email) + "&channel_id=" + Str(cnId).Trim()
end function

' Sin body: el token va en el query string (verificado en player.js:1370).
function tvApiDesvincularUrl(baseUrl as string, token as string) as string
    return tvJoinUrl(baseUrl, "api/desvincular") + "?token=" + tvUrlEncode(token)
end function

' Heartbeat cada 15s (CU-16). No es un endpoint REST: es un .json colgando del token.
function tvApiDashboardUrl(baseUrl as string, token as string, cnId as integer) as string
    return tvJoinUrl(baseUrl, token + "/" + Str(cnId).Trim() + ".json")
end function

function tvApiChannelAllowedIpUrl(baseUrl as string) as string
    return tvJoinUrl(baseUrl, "api/channel-allowed-ip")
end function

' Body real: {ip, cn_id} — NO {user_id, channel_id, ip}, que es lo que decía una auditoría previa.
function tvApiChannelAllowedIpBody(ip as string, cnId as integer) as string
    return FormatJson({ ip: ip, cn_id: cnId })
end function

function tvApiMultiCdnUrl(baseUrl as string) as string
    return tvJoinUrl(baseUrl, "api/get-ipurl")
end function

' `deviceid` va SIEMPRE a 1, está así de fijo en el original (player.js:1343). No es el id del equipo.
function tvApiMultiCdnBody(deviceIp as string) as string
    return FormatJson({ deviceid: 1, networkid: deviceIp })
end function

function tvApiNotificationsUrl(notificationsUrl as string) as string
    return tvJoinUrl(notificationsUrl, "api/firebase/getListNotificationUser")
end function

function tvApiMarkReadUrl(notificationsUrl as string) as string
    return tvJoinUrl(notificationsUrl, "api/firebase/markRead")
end function

' ---- helpers -----------------------------------------------------------------

' Une base y ruta sin depender de si la base trae barra final (los config de los ISP van variados).
function tvJoinUrl(baseUrl as string, path as string) as string
    if baseUrl = "" then return path
    base = baseUrl
    if Right(base, 1) = "/" then base = Left(base, Len(base) - 1)
    p = path
    if Left(p, 1) = "/" then p = Mid(p, 2)
    return base + "/" + p
end function

' Percent-encoding propio: `roUrlTransfer.Escape()` solo existe en el dispositivo, y esto tiene que
' poder testearse en el PC. Importa de verdad — las contraseñas traen `&`, `+`, `#` y espacios, y sin
' escapar romperían el query string (el usuario vería "credenciales incorrectas" con la clave buena).
function tvUrlEncode(value as string) as string
    if value = "" then return ""
    out = ""
    for i = 1 to Len(value)
        ch = Mid(value, i, 1)
        code = Asc(ch)
        ' Sin reservar: A-Z a-z 0-9 - _ . ~
        if (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or ch = "-" or ch = "_" or ch = "." or ch = "~"
            out = out + ch
        else
            out = out + tvPercentEncodeChar(code)
        end if
    end for
    return out
end function

function tvPercentEncodeChar(code as integer) as string
    ' UTF-8 de un solo byte; para code points altos se codifica el byte tal cual, que es lo que
    ' necesitan email y contraseña en la práctica.
    return "%" + tvToHex2(code)
end function

function tvToHex2(n as integer) as string
    digits = "0123456789ABCDEF"
    hi = Int(n / 16)
    lo = n mod 16
    if hi > 15 then hi = 15
    return Mid(digits, hi + 1, 1) + Mid(digits, lo + 1, 1)
end function
