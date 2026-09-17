' Reglas de sesión (CU-01, CU-04). Puras y testeables; el acceso al registro vive en data/local.

' ---- deviceId ----------------------------------------------------------------
'
' El `devid` NUNCA fue una MAC, aunque la clave del original se llame así: es un número aleatorio de
' 10 dígitos que se genera una vez y se persiste (login.js:45-56). No hay ninguna dependencia de
' hardware que resolver.
'
' Detalle de portabilidad: el original hace getRandomCode(1000000000, 9999999999), y 9999999999 NO
' CABE en un Integer de BrightScript (máximo 2.147.483.647). Por eso se construye como TEXTO de 10
' dígitos en vez de como número.

function tvGenerateDeviceId() as string
    id = Str(Rnd(9)).Trim()                  ' primer dígito 1-9, para que sean 10 de verdad
    for i = 2 to 10
        id = id + Str(Rnd(10) - 1).Trim()    ' Rnd(10) da 1-10 → 0-9
    end for
    return id
end function

' Se regenera si no hay ninguno o si el guardado trae un guion: las versiones viejas del original
' llegaron a guardar una MAC ahí, y esas hay que descartarlas (login.js:45-49).
function tvIsValidDeviceId(deviceId as object) as boolean
    if deviceId = invalid then return false
    if not tvIsString(deviceId) then return false
    if deviceId = "" then return false
    if Instr(1, deviceId, "-") > 0 then return false
    return true
end function

' ---- logout ------------------------------------------------------------------
'
' Al cerrar sesión se borra todo MENOS lo que sobrevive a propósito (player.js:1209-1227):
'   - deviceId: SIEMPRE. Si se regenera, el backend ve un aparato nuevo en cada login.
'   - email / password / remember: solo si "recordarme" estaba activo.
'
' El password de SESIÓN (el que se necesita en cada get-web2) no está aquí: ese se borra siempre.
' Son dos cosas distintas con ciclos de vida distintos, y confundirlas es un error clásico.
function tvKeysToPreserveOnLogout(rememberMe as boolean) as object
    keys = ["deviceId"]
    if rememberMe
        keys.Push("email")
        keys.Push("password")
        keys.Push("rememberMe")
    end if
    return keys
end function

function tvShouldKeepKeyOnLogout(key as string, rememberMe as boolean) as boolean
    for each k in tvKeysToPreserveOnLogout(rememberMe)
        if k = key then return true
    end for
    return false
end function

' ---- validación del formulario de login --------------------------------------
'
' Mismas comprobaciones que el original antes de gastar una llamada: email con forma y password no
' vacío (login.js:33-45). Devuelve "" si todo bien, o el mensaje a mostrar.
function tvValidateLoginForm(email as string, password as string) as string
    if not tvLooksLikeEmail(email) then return "Ingrese un email válido"
    if password.Trim() = "" then return "Ingrese su contraseña"
    return ""
end function

function tvLooksLikeEmail(email as string) as boolean
    if email = invalid or email = "" then return false
    at = Instr(1, email, "@")
    if at < 2 then return false                        ' algo antes de la arroba
    dot = Instr(at, email, ".")
    if dot = 0 then return false                       ' y un punto después
    if dot = at + 1 then return false                  ' con dominio entre medias
    if dot = Len(email) then return false              ' y algo después del punto
    if Instr(at + 1, email, "@") > 0 then return false ' una sola arroba
    return true
end function
