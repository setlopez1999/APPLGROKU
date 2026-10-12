' Sesión persistida en el registro del Roku. Reemplaza al `localStorage` del original.
'
' ⚠ Esta capa toca el dispositivo: no se ejecuta en `npm test`. Las REGLAS (qué se conserva al
' cerrar sesión, cómo es un deviceId válido) están en domain/usecase/SessionRules.brs y sí se
' testean. Aquí solo está el acceso al registro.
'
' LÍMITE DURO: el registro son 32 KB para TODO el canal (docs/ROKU-GOTCHAS.md §5). Por eso aquí solo
' se guarda lo mínimo — deviceId, email, password cifrado y flags. El `UserInfo` completo vive en
' memoria y se recarga de get-web2 al arrancar; el original lo metía entero en localStorage y ese
' JSON, en un ISP con muchos canales, se acerca al límite.

' La seccion lleva el nombre del ISP (proveedor + cliente, de ENV/config.txt).
'
' Estaba fija en "tvvisor", y eso hacia que dos ISP sideloadeados en el mismo hueco de desarrollo
' COMPARTIERAN registro: las credenciales recordadas de uno aparecian en el otro. En produccion
' cada ISP es un canal distinto y no pasaria, pero al probar desconcierta bastante.
function tvRegistrySectionName() as string
    nombre = "tvvisor"
    if m.global <> invalid and m.global.brand <> invalid
        propia = m.global.brand.registrySection
        if propia <> invalid and propia <> "" then nombre = propia
    end if
    return nombre
end function

function tvRegistrySection() as object
    nombre = tvRegistrySectionName()
    seccion = CreateObject("roRegistrySection", nombre)

    ' MIGRACION desde la seccion antigua, una sola vez.
    '
    ' Sin esto, renombrar la seccion deja la instalacion existente sin sesion y —lo grave— SIN
    ' deviceId. El deviceId es del APARATO, no de la cuenta: si se regenera, el operador cuenta un
    ' equipo nuevo y la cuenta agota su limite de dispositivos vinculados. Ya paso una vez.
    if nombre <> "tvvisor" and not seccion.Exists("migrado")
        vieja = CreateObject("roRegistrySection", "tvvisor")
        for each clave in vieja.GetKeyList()
            if not seccion.Exists(clave) then seccion.Write(clave, vieja.Read(clave))
        end for
        seccion.Write("migrado", "1")
        seccion.Flush()
        print "[TV] registro: migrado de 'tvvisor' a '"; nombre; "'"
    end if

    return seccion
end function

function tvRegistryRead(key as string, fallback = "" as string) as string
    section = tvRegistrySection()
    if not section.Exists(key) then return fallback
    value = section.Read(key)
    if value = invalid then return fallback
    return value
end function

sub tvRegistryWrite(key as string, value as string)
    section = tvRegistrySection()
    section.Write(key, value)
    section.Flush()
end sub

sub tvRegistryDelete(key as string)
    section = tvRegistrySection()
    if section.Exists(key)
        section.Delete(key)
        section.Flush()
    end if
end sub

' ---- deviceId ----------------------------------------------------------------

' Lee el deviceId; si no hay o no vale (p. ej. una MAC de versiones viejas), genera uno y lo guarda.
function tvSessionDeviceId() as string
    stored = tvRegistryRead("deviceId")
    if tvIsValidDeviceId(stored) then return stored

    fresh = tvGenerateDeviceId()
    tvRegistryWrite("deviceId", fresh)
    return fresh
end function

' ---- password de sesión ------------------------------------------------------
'
' El backend exige el password EN CLARO en cada get-web2, no solo en el login
' (docs/BACKEND-GOTCHAS.md §11). Así que hay que conservarlo toda la sesión activa, cifrado, y esto
' es INDEPENDIENTE del "recordarme": son dos conceptos con ciclos de vida distintos.

sub tvSessionSetPassword(password as string)
    tvRegistryWrite("sessionPassword", tvEncryptSecret(password))
end sub

function tvSessionPassword() as string
    return tvDecryptSecret(tvRegistryRead("sessionPassword"))
end function

' ---- credenciales de "recordarme" --------------------------------------------

sub tvSessionSetRemembered(email as string, password as string, remember as boolean)
    if remember
        tvRegistryWrite("rememberMe", "true")
        tvRegistryWrite("email", email)
        tvRegistryWrite("password", tvEncryptSecret(password))
    else
        tvRegistryWrite("rememberMe", "false")
        tvRegistryDelete("email")
        tvRegistryDelete("password")
    end if
end sub

function tvSessionRemembered() as object
    return {
        rememberMe: tvRegistryRead("rememberMe") = "true"
        email: tvRegistryRead("email")
        password: tvDecryptSecret(tvRegistryRead("password"))
    }
end function

' ---- PIN parental (CU-14) ---------------------------------------------------
'
' Se guarda el sha256 del PIN con el deviceId como sal, nunca el PIN en claro. No es bcrypt, pero
' bcrypt no existe en Roku (ver domain/usecase/ParentalPin.brs) y para 4 dígitos la diferencia
' práctica es pequeña: el ataque real es probar 10.000 combinaciones, no romper el hash.

sub tvSetParentalPin(pin as string)
    tvRegistryWrite("parentalPin", tvSha256Hex(pin + tvRegistryRead("deviceId")))
end sub

function tvHasParentalPin() as boolean
    return tvRegistryRead("parentalPin") <> ""
end function

function tvParentalPinMatches(pin as string) as boolean
    guardado = tvRegistryRead("parentalPin")
    if guardado = "" then return false
    return guardado = tvSha256Hex(pin + tvRegistryRead("deviceId"))
end function

' ---- cierre de sesión --------------------------------------------------------

' Borra todo salvo lo que debe sobrevivir, según las reglas testeadas en SessionRules.
sub tvSessionClear()
    remember = tvRegistryRead("rememberMe") = "true"
    section = tvRegistrySection()

    for each key in section.GetKeyList()
        if not tvShouldKeepKeyOnLogout(key, remember) then section.Delete(key)
    end for
    section.Flush()
end sub

' ---- cifrado -----------------------------------------------------------------
'
' AES vía roEVPCipher, con clave derivada del deviceId. No busca compatibilidad con el AES del
' original (era otro aparato y otra clave): busca que el password no quede en claro en el registro.
'
' ⚠ PENDIENTE DE VERIFICAR EN DISPOSITIVO. Si `roEVPCipher` no se comporta como aquí se asume, el
' fallback devuelve el valor tal cual — mejor una sesión que funciona sin cifrar que una sesión rota,
' que es además lo que hacía el original (guardaba el password en texto plano).

function tvEncryptSecret(plain as string) as string
    if plain = "" then return ""

    cipher = tvCreateCipher(true)
    if cipher = invalid then return plain

    bytes = CreateObject("roByteArray")
    bytes.FromAsciiString(plain)
    encrypted = cipher.Process(bytes)
    if encrypted = invalid then return plain

    return "enc:" + encrypted.ToHexString()
end function

function tvDecryptSecret(stored as string) as string
    if stored = "" then return ""
    if Left(stored, 4) <> "enc:" then return stored     ' guardado sin cifrar por el fallback

    cipher = tvCreateCipher(false)
    if cipher = invalid then return ""

    bytes = CreateObject("roByteArray")
    bytes.FromHexString(Mid(stored, 5))
    decrypted = cipher.Process(bytes)
    if decrypted = invalid then return ""

    return decrypted.ToAsciiString()
end function

function tvCreateCipher(encrypt as boolean) as object
    deviceId = tvRegistryRead("deviceId")
    if deviceId = "" then return invalid

    key = tvSha256Hex(deviceId + "tv-visor-roku")       ' 64 hex = 32 bytes → AES-256
    iv = Left(tvSha256Hex(deviceId), 32)                ' 32 hex = 16 bytes

    cipher = CreateObject("roEVPCipher")
    if cipher = invalid then return invalid
    if cipher.Setup(encrypt, "aes-256-cbc", key, iv, 1) <> 0 then return invalid
    return cipher
end function

function tvSha256Hex(value as string) as string
    digest = CreateObject("roEVPDigest")
    digest.Setup("sha256")
    bytes = CreateObject("roByteArray")
    bytes.FromAsciiString(value)
    return digest.Process(bytes)
end function

' ---- CU-01/CU-03: sesión persistente -----------------------------------------
'
' Lo que se guarda es el ASIDERO de la sesión —correo y token—, NO la sesión entera.
'
' El original metía el `UserInfo` completo en localStorage, catálogo incluido. Aquí no cabe: el
' registro del Roku son 32 KB para todo el canal, y el catálogo de un ISP mediano se los come
' (docs/ROKU-GOTCHAS.md §5). Con el asidero basta: al arrancar se pide get-web2 con el token y el
' servidor devuelve plan y catálogo frescos, que es justo lo que la revalidación hace cada minuto.
'
' Efecto para el usuario, que es lo que pide CU-01: cerrar la app y volver a abrirla entra directo
' a la televisión, sin bienvenida y sin escribir nada.

sub tvSessionSaveHandle(email as string, token as string)
    tvRegistryWrite("sessionEmail", email)
    tvRegistryWrite("sessionToken", token)
end sub

function tvSessionHandle() as object
    return {
        email: tvRegistryRead("sessionEmail")
        token: tvRegistryRead("sessionToken")
        password: tvSessionPassword()
    }
end function
