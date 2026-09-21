' CU-14 — Control parental.
'
' POR QUÉ EL PIN ES LOCAL Y NO EL DEL BACKEND (decisión del 2026-09-21):
' el backend manda `parentlockcode` como hash **bcrypt** con coste 10 (`$2y$10$...`). Verificarlo
' exige ~2^10 expansiones de clave de Blowfish, y Roku solo expone md5/sha1/sha256 y AES. Se puede
' escribir Blowfish a mano en BrightScript, pero tardaría MINUTOS por intento: inservible con un
' mando en la mano.
'
' Así que el canal gestiona su propio PIN, guardado cifrado en el registro del aparato. Es la única
' salida que no depende del backend, y cumple el propósito real de un control parental en una TV:
' proteger de un niño en casa, no de un atacante remoto.
'
' PEAJE, y hay que decírselo al usuario al crearlo: este PIN **no es el mismo** que el configurado
' en el móvil o en la web. El día que el backend exponga un endpoint de validación se cambia SOLO
' este archivo y vuelven a coincidir.

' Un PIN válido son exactamente 4 dígitos, como en el resto de las apps del sistema.
function tvIsValidPinFormat(pin as object) as boolean
    if pin = invalid then return false
    if not tvIsString(pin) then return false
    if Len(pin) <> 4 then return false

    for i = 1 to 4
        codigo = Asc(Mid(pin, i, 1))
        if codigo < 48 or codigo > 57 then return false
    end for
    return true
end function

' Qué hacer cuando alguien intenta abrir un canal de adultos:
'
'   "allow"   ya se validó en esta sesión → pasa sin preguntar
'   "create"  no hay PIN guardado todavía → hay que crearlo
'   "ask"     hay PIN → pedirlo
'
' Lo de desbloquear POR SESIÓN viene del port a Kotlin: pedir el PIN en CADA selección de canal
' adulto es insufrible con un mando. Se reinicia al cerrar sesión.
function tvParentalStep(hasPin as boolean, unlockedThisSession as boolean) as string
    if unlockedThisSession then return "allow"
    if not hasPin then return "create"
    return "ask"
end function

' Mensaje del modal según el paso.
function tvParentalTitle(paso as string) as string
    if paso = "create" then return "Crea tu PIN parental"
    return "Introduce tu PIN parental"
end function

function tvParentalMessage(paso as string) as string
    if paso = "create"
        return "Este canal es para adultos. Crea un PIN de 4 dígitos para protegerlo. Se guarda solo en este dispositivo, así que no es el mismo que tengas configurado en el móvil o en la web."
    end if
    return "Introduce tu PIN de 4 dígitos para ver este canal."
end function

' Resultado de un intento. Se separa del acceso al registro para poder testearlo.
function tvCheckPinAttempt(paso as string, pin as object, matches as boolean) as object
    if not tvIsValidPinFormat(pin)
        return { ok: false, error: "El PIN debe tener 4 dígitos" }
    end if

    if paso = "create" then return { ok: true, error: "", guardar: true }

    if not matches
        return { ok: false, error: "PIN incorrecto" }
    end if

    return { ok: true, error: "", guardar: false }
end function
