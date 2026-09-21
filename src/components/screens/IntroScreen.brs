' Intro de marca. Ver IntroScreen.xml.
'
' ⚠ Toca el dispositivo: no se ejecuta en `npm test`.

sub init()
    m.brand = m.global.brand

    m.top.findNode("bg").uri = m.brand.introUri
    m.top.findNode("scrim").color = "0x000000A6"

    ' Igual que en el login: el texto es el FALLBACK del logo, no un añadido.
    hayLogo = (m.brand.logoUri <> "")

    logo = m.top.findNode("logo")
    logo.uri = m.brand.logoUri
    logo.visible = hayLogo

    nombre = m.top.findNode("nombre")
    nombre.text = tvBrandText(m.brand)
    nombre.color = m.brand.textPrimary
    nombre.visible = not hayLogo

    m.salir = m.top.findNode("salir")
    m.salir.observeField("fire", "onFin")
    m.salir.control = "start"
end sub

sub onFin()
    m.salir.control = "stop"
    m.top.done = true
end sub

' Cualquier tecla la salta: una intro que no se puede saltar molesta a partir de la segunda vez.
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    onFin()
    return true
end function
