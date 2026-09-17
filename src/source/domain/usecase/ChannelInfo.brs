' CU-13 — Información del canal en emisión (lo que pinta el bloque de info y el footer).
'
' Devuelve un modelo YA LISTO para la vista: textos formateados y el progreso en porcentaje. La vista
' no calcula nada, solo dibuja — así el diseño se puede cambiar sin tocar esta lógica (PLAN.md §6.5).
'
' Si no hay EPG para ese canal, el original muestra "Programación de {nombre}" en los dos huecos
' (actual y siguiente) en vez de dejarlos vacíos. Se replica: con 6 de 57 canales con guía en algunos
' ISP, este es el caso NORMAL, no el excepcional.

function tvBuildChannelInfo(channel as object, programs as object, nowSec as longinteger, utcOffsetSec = 0 as integer) as object
    if channel = invalid then return tvEmptyChannelInfo()

    fallback = "Programación de " + channel.nombre
    info = {
        cnId: channel.cnId
        numero: channel.numero
        nombre: channel.nombre
        logo: channel.imagen
        esRadio: channel.audio = 1

        ahoraTitulo: fallback
        ahoraInicio: ""
        ahoraFin: ""
        progreso: 0
        tieneAhora: false

        siguienteTitulo: fallback
        siguienteInicio: ""
        siguienteFin: ""
        tieneSiguiente: false
    }

    current = tvCurrentProgram(programs, nowSec)
    if current <> invalid
        info.ahoraTitulo = current.titulo
        info.ahoraInicio = tvFormatTime12h(current.fechaIni, utcOffsetSec)
        info.ahoraFin = tvFormatTime12h(current.fechaFin, utcOffsetSec)
        info.progreso = tvPercentElapsed(current.fechaIni, current.fechaFin, nowSec)
        info.tieneAhora = true

        ' `next` es palabra reservada en BrightScript (for...next): la variable va en español.
        siguiente = tvNextProgram(programs, current.fechaFin)
        if siguiente <> invalid
            info.siguienteTitulo = siguiente.titulo
            info.siguienteInicio = tvFormatTime12h(siguiente.fechaIni, utcOffsetSec)
            info.siguienteFin = tvFormatTime12h(siguiente.fechaFin, utcOffsetSec)
            info.tieneSiguiente = true
        end if
    end if

    return info
end function

function tvEmptyChannelInfo() as object
    return {
        cnId: 0
        numero: 0
        nombre: ""
        logo: ""
        esRadio: false
        ahoraTitulo: ""
        ahoraInicio: ""
        ahoraFin: ""
        progreso: 0
        tieneAhora: false
        siguienteTitulo: ""
        siguienteInicio: ""
        siguienteFin: ""
        tieneSiguiente: false
    }
end function
