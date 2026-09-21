' CU-14 — PIN parental. Ver PinModal.xml.
'
' ⚠ Toca el dispositivo: no se ejecuta en `npm test`. Las reglas (formato del PIN, qué paso toca,
' resultado del intento) están en domain/usecase/ParentalPin.brs, que sí tiene tests.

sub init()
    m.brand = m.global.brand

    m.top.findNode("scrim").color = "0x000000D9"
    m.top.findNode("panel").color = m.brand.surface

    m.titulo = m.top.findNode("titulo")
    m.mensaje = m.top.findNode("mensaje")
    m.error = m.top.findNode("error")
    m.titulo.color = m.brand.textPrimary
    m.mensaje.color = m.brand.textSecondary
    m.top.findNode("pista").color = m.brand.textSecondary
    m.error.color = m.brand.liveNow

    m.teclado = m.top.findNode("teclado")
    ' Oculto: en una TV el PIN lo ve toda la habitación.
    m.teclado.secureMode = true
end sub

sub onPasoChanged()
    m.titulo.text = tvParentalTitle(m.top.paso)
    m.mensaje.text = tvParentalMessage(m.top.paso)
    m.error.text = ""
    m.teclado.text = ""
    m.teclado.setFocus(true)
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if key = "back"
        intentar()
        return true
    end if

    ' El resto de teclas son del teclado.
    return false
end function

sub intentar()
    pin = m.teclado.text
    resultado = tvCheckPinAttempt(m.top.paso, pin, tvParentalPinMatches(pin))

    if not resultado.ok
        m.error.text = resultado.error
        m.teclado.text = ""
        m.teclado.setFocus(true)
        return
    end if

    if resultado.guardar then tvSetParentalPin(pin)

    m.error.text = ""
    m.top.action = "ok"
end sub

' Salir sin validar: lo llama la escena cuando el usuario abandona.
sub cancelar()
    m.top.action = "cancel"
end sub
