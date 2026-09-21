' Información del canal en emisión. Ver CurrentChannelDisplay.xml.
'
' ⚠ Toca el dispositivo: no se ejecuta en `npm test`. Los textos y el progreso vienen ya calculados
' de domain/usecase/ChannelInfo.brs, que sí está probado.

sub init()
    m.brand = m.global.brand

    m.logo = m.top.findNode("logo")
    m.number = m.top.findNode("number")
    m.name = m.top.findNode("name")
    m.programTitle = m.top.findNode("programTitle")
    m.programTime = m.top.findNode("programTime")
    m.progressTrack = m.top.findNode("progressTrack")
    m.progressFill = m.top.findNode("progressFill")
    m.nextLabel = m.top.findNode("nextLabel")

    m.number.color = m.brand.textSecondary
    m.name.color = m.brand.textPrimary
    m.programTitle.color = m.brand.textPrimary
    m.programTime.color = m.brand.textSecondary
    m.nextLabel.color = m.brand.textSecondary

    m.progressTrack.color = m.brand.surfaceVariant
    ' El rojo de "en emisión" es un token fijo, no el color del ISP.
    m.progressFill.color = m.brand.liveNow

    m.favBg = m.top.findNode("favBg")
    m.favLabel = m.top.findNode("favLabel")
    m.fullBg = m.top.findNode("fullBg")
    m.fullLabel = m.top.findNode("fullLabel")

    m.buttons = [{ bg: m.favBg, label: m.favLabel, id: "mylist" }, { bg: m.fullBg, label: m.fullLabel, id: "fullscreen" }]
    m.focusIndex = 0

    onFocusChanged()
end sub

sub onInfoChanged()
    info = m.top.info
    if info = invalid then return

    m.logo.uri = info.logo
    m.number.text = Str(info.numero).Trim()
    m.name.text = info.nombre
    m.programTitle.text = info.ahoraTitulo

    if info.tieneAhora
        m.programTime.text = info.ahoraInicio + " - " + info.ahoraFin
    else
        ' Sin guía no se inventan horarios: en varios ISP este es el caso normal, no el raro.
        m.programTime.text = ""
    end if

    ' El ancho de la barra es el porcentaje del track (700 px de DISENO).
    m.progressFill.width = Int((700 * info.progreso) / 100)

    if info.tieneSiguiente
        m.nextLabel.text = "A continuación: " + info.siguienteTitulo + "  " + info.siguienteInicio
    else
        m.nextLabel.text = ""
    end if

    if m.top.isFavorite
        m.favLabel.text = "En Mi lista"
    else
        m.favLabel.text = "Mi lista"
    end if

    onFocusChanged()
end sub

sub onFocusChanged()
    for i = 0 to m.buttons.Count() - 1
        button = m.buttons[i]
        if m.top.barFocused and i = m.focusIndex
            button.bg.color = m.brand.focusOutline
            button.label.color = m.brand.pillActiveText
        else
            button.bg.color = m.brand.controlSurface
            button.label.color = m.brand.textPrimary
        end if
    end for
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if key = "right"
        if m.focusIndex < m.buttons.Count() - 1
            m.focusIndex = m.focusIndex + 1
            onFocusChanged()
        end if
        return true
    end if

    if key = "left"
        if m.focusIndex > 0
            m.focusIndex = m.focusIndex - 1
            onFocusChanged()
        end if
        return true
    end if

    if key = "OK"
        m.top.action = m.buttons[m.focusIndex].id
        return true
    end if

    ' Arriba/abajo se dejan pasar para que el foco salga de la fila.
    return false
end function
