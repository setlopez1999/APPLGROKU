' CU-13 — La franja del canal. Ver ChannelStrip.xml.
'
' ⚠ Toca el dispositivo: no se ejecuta en `npm test`. Todo lo que decide QUÉ texto va aquí está en
' domain/usecase/ChannelInfo.brs, que sí tiene tests.

sub init()
    m.brand = m.global.brand

    m.top.findNode("veil").color = "0x000000C4"

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
    ' El rojo de "en emisión" es un token fijo, no el color del ISP (DISENO.md §1).
    m.progressFill.color = m.brand.liveNow
end sub

sub onInfoChanged()
    info = m.top.info
    if info = invalid then return

    m.logo.uri = info.logo
    m.number.text = Str(info.numero).Trim()
    m.name.text = info.nombre

    ' Sin guía esto trae "Programación de {canal}", que es TEXTO y no un hueco: un espacio en
    ' blanco se lee como un error de carga (CU-13).
    m.programTitle.text = info.ahoraTitulo

    if info.tieneAhora
        m.programTime.text = info.ahoraInicio + " - " + info.ahoraFin
        m.progressTrack.visible = true
    else
        m.programTime.text = ""
        m.progressTrack.visible = false
    end if

    m.progressFill.width = Int((700 * info.progreso) / 100)

    ' "A continuación" está casi siempre vacío en los ISP actuales: el backend apenas publica
    ' programación futura. No es un fallo de la app (09-LIMITES).
    if info.tieneSiguiente
        m.nextLabel.text = "A continuación: " + info.siguienteTitulo + "  " + info.siguienteInicio
    else
        m.nextLabel.text = ""
    end if
end sub
