' Modal reutilizable. Ver AppModal.xml.
'
' ⚠ Toca el dispositivo: no se ejecuta en `npm test`.

sub init()
    m.brand = m.global.brand

    m.top.findNode("scrim").color = "0x000000CC"
    m.top.findNode("panel").color = m.brand.surface

    m.titulo = m.top.findNode("titulo")
    m.mensaje = m.top.findNode("mensaje")
    m.titulo.color = m.brand.textPrimary
    m.mensaje.color = m.brand.textSecondary

    m.boton = m.top.findNode("boton")
    m.botonFondo = m.top.findNode("botonFondo")
    m.botonTexto = m.top.findNode("botonTexto")

    ' El botón es el único elemento con el color de marca (DISENO §1), y al ser lo único enfocable
    ' del modal se dibuja siempre como enfocado.
    m.botonFondo.color = m.brand.accent
    m.botonTexto.color = m.brand.pillActiveText
end sub

sub onContentChanged()
    m.titulo.text = m.top.titulo
    m.mensaje.text = m.top.mensaje

    ' Sin texto de botón es un modal informativo: se sale con ATRÁS y no se dibuja nada que pulsar.
    tieneBoton = (m.top.botonTexto <> "")
    m.boton.visible = tieneBoton
    m.botonTexto.text = m.top.botonTexto
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if key = "OK"
        if m.top.botonTexto <> ""
            m.top.action = "accept"
        else
            m.top.action = "close"
        end if
        return true
    end if

    if key = "back"
        m.top.action = "close"
        return true
    end if

    ' El modal se come TODO lo demás: mientras está abierto no se navega por detrás.
    return true
end function
