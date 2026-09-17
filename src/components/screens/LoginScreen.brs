' CU-01 — Login. Ver LoginScreen.xml.
'
' ⚠ Toca el dispositivo: no se ejecuta en `npm test`. La lógica que SÍ está probada vive en
' domain/usecase/SessionRules.brs (validación del formulario, deviceId) y en
' data/remote/ApiRoutes.brs (construcción de la url). Aquí solo hay pegamento y foco.

sub init()
    m.brand = m.global.brand

    ' --- marca y fondo ---
    m.top.findNode("bg").uri = m.brand.loginUri
    m.top.findNode("scrim").color = "0x000000B3"      ' oscurece el fondo para que el texto se lea

    logo = m.top.findNode("logo")
    logo.uri = m.brand.logoUri

    brandName = m.top.findNode("brandName")
    brandName.text = m.brand.appName + " " + m.brand.appBadge
    brandName.color = m.brand.textPrimary
    m.top.findNode("brandTagline").color = m.brand.textSecondary

    ' --- tarjeta del formulario ---
    m.top.findNode("card").color = m.brand.surface
    m.top.findNode("title").color = m.brand.textPrimary
    m.top.findNode("subtitle").color = m.brand.textSecondary

    ' --- campos ---
    m.emailValue = m.top.findNode("emailValue")
    m.passwordValue = m.top.findNode("passwordValue")
    m.errorLabel = m.top.findNode("errorLabel")
    m.submitLabel = m.top.findNode("submitLabel")

    for each id in ["emailField", "passwordField"]
        m.top.findNode(id).color = m.brand.surfaceVariant
    end for
    for each id in ["emailLabel", "passwordLabel"]
        m.top.findNode(id).color = m.brand.textSecondary
    end for
    m.emailValue.color = m.brand.textPrimary
    m.passwordValue.color = m.brand.textPrimary
    m.errorLabel.color = m.brand.liveNow

    ' El botón es el único elemento con el color de marca (DISENO §1).
    m.top.findNode("submitButton").color = m.brand.accent
    m.submitLabel.color = m.brand.pillActiveText

    ' Marco de foco: BLANCO fijo y del mismo grosor en toda la app, no depende del ISP.
    m.focusFrames = ["emailFocus", "passwordFocus", "submitFocus"]
    for each id in m.focusFrames
        m.top.findNode(id).color = m.brand.focusOutline
    end for

    ' --- teclado ---
    m.keyboardLayer = m.top.findNode("keyboardLayer")
    m.top.findNode("keyboardScrim").color = "0x000000D9"
    m.keyboard = m.top.findNode("keyboard")
    m.top.findNode("keyboardHint").color = m.brand.textSecondary
    m.editingField = ""

    ' --- estado ---
    m.email = ""
    m.password = ""
    m.rememberMe = true
    m.focusIndex = 0
    m.busy = false

    prefillFromRegistry()
    refresh()
end sub

' "Recordarme" del original: si estaba activo, el correo y la clave vuelven rellenados.
' NO se envía solo: el usuario confirma. Auto-enviar deja al usuario sin forma de corregir si las
' credenciales guardadas ya no valen.
sub prefillFromRegistry()
    saved = tvSessionRemembered()
    if saved.rememberMe
        m.email = saved.email
        m.password = saved.password
        m.rememberMe = true
    end if
end sub

sub refresh()
    if m.email <> ""
        m.emailValue.text = m.email
        m.emailValue.color = m.brand.textPrimary
    else
        m.emailValue.text = "tu@email.com"
        m.emailValue.color = m.brand.textDisabled
    end if

    ' La contraseña nunca se muestra en claro: en una TV la ve toda la habitación.
    m.passwordValue.text = maskedPassword()

    for i = 0 to m.focusFrames.Count() - 1
        m.top.findNode(m.focusFrames[i]).visible = (i = m.focusIndex)
    end for
end sub

function maskedPassword() as string
    out = ""
    for i = 1 to Len(m.password)
        out = out + "*"
    end for
    return out
end function

' ---- foco y teclas -----------------------------------------------------------

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    ' Con el teclado abierto, ATRÁS confirma lo escrito y vuelve al formulario.
    if m.keyboardLayer.visible
        if key = "back"
            commitKeyboard()
            return true
        end if
        return false      ' el resto de teclas son del teclado
    end if

    if m.busy then return true     ' durante la llamada no se toca nada

    if key = "down"
        if m.focusIndex < 2 then m.focusIndex = m.focusIndex + 1
        refresh()
        return true
    end if

    if key = "up"
        if m.focusIndex > 0 then m.focusIndex = m.focusIndex - 1
        refresh()
        return true
    end if

    if key = "OK"
        if m.focusIndex = 0 then openKeyboard("email")
        if m.focusIndex = 1 then openKeyboard("password")
        if m.focusIndex = 2 then submit()
        return true
    end if

    return false
end function

sub openKeyboard(field as string)
    m.editingField = field
    m.keyboard.secureMode = (field = "password")

    if field = "email"
        m.keyboard.text = m.email
    else
        m.keyboard.text = m.password
    end if

    m.keyboardLayer.visible = true
    m.keyboard.setFocus(true)
end sub

sub commitKeyboard()
    if m.editingField = "email"
        m.email = m.keyboard.text
    else if m.editingField = "password"
        m.password = m.keyboard.text
    end if

    m.keyboardLayer.visible = false
    m.editingField = ""
    m.top.setFocus(true)
    refresh()
end sub

' ---- envío -------------------------------------------------------------------

sub submit()
    ' Validación local antes de gastar una llamada (misma que el original).
    problema = tvValidateLoginForm(m.email, m.password)
    if problema <> ""
        m.errorLabel.text = problema
        return
    end if

    m.errorLabel.text = ""
    m.busy = true
    m.submitLabel.text = "Iniciando sesión..."

    url = tvApiGetWeb2Url(m.brand.baseUrl, m.email, m.password, tvSessionDeviceId(), m.brand.platform)

    m.loginTask = CreateObject("roSGNode", "ApiTask")
    m.loginTask.observeField("response", "onLoginResponse")
    m.loginTask.request = tvApiRequest(url)
    m.loginTask.control = "RUN"
end sub

sub onLoginResponse()
    m.busy = false
    m.submitLabel.text = "Ingresar"

    response = m.loginTask.response

    if not response.ok
        ' Se distingue el fallo de transporte del de credenciales: el primero suele ser el
        ' certificado o la red, y decirle "credenciales incorrectas" al usuario despista.
        if response.error = "tls"
            m.errorLabel.text = "No se pudo conectar con el servicio"
        else
            m.errorLabel.text = "Error al conectarse con el servicio"
        end if
        return
    end if

    json = response.json
    if json = invalid
        m.errorLabel.text = "Respuesta no válida del servicio"
        return
    end if

    ' El backend manda el fallo con `error:true` y HTTP 200.
    if ResponseHasError(json)
        m.errorLabel.text = ResponseErrorMessage(json)
        return
    end if

    ' El password se guarda cifrado SIEMPRE, no solo si hay "recordarme": el backend lo vuelve a
    ' pedir en cada get-web2 de la revalidación (docs/BACKEND-GOTCHAS.md §11). Son dos cosas
    ' distintas con ciclos de vida distintos.
    tvSessionSetPassword(m.password)
    tvSessionSetRemembered(m.email, m.password, m.rememberMe)

    m.top.session = {
        userInfo: UserInfoFromJson(json)
        raw: json
    }
end sub
