' Ventana de celdas de la parrilla de "TV en directo". Réplica de LiveViewModel.buildEpg() del
' rediseño Kotlin (ver docs/DISENO.md §2.4).
'
' DECISIÓN DE DISEÑO IMPORTANTE (cierra la §8.3 de plan_migracion.md): la parrilla NO dibuja celdas
' de ancho proporcional a la duración. Usa un número FIJO de columnas por fila —unas pasadas
' (catch-up), la de AHORA y unas futuras—, y eso se porta a SceneGraph sin pelearse con el layout.
'
' La ventana es MALEABLE: el número de columnas se ajusta a lo que hay de verdad, con un tope. Si el
' ISP no manda nada pasado, no se dibuja ninguna columna pasada — así no quedan cuadros vacíos.

function EPG_PAST_COLUMNS() as integer
    return 3
end function

function EPG_FUTURE_COLUMNS() as integer
    return 1
end function

' Índice del programa en emisión, o -1 si hay un hueco en la guía.
function tvCurrentProgramIndex(programs as object, nowSec as longinteger) as integer
    if programs = invalid then return -1
    for i = 0 to programs.Count() - 1
        if tvIsWithinRange(programs[i].fechaIni, programs[i].fechaFin, nowSec) then return i
    end for
    return -1
end function

' "09:00 AM - 12:00 PM"
function tvProgramTimeRange(program as object, utcOffsetSec = 0 as integer) as string
    if program = invalid then return ""
    return tvFormatTime12h(program.fechaIni, utcOffsetSec) + " - " + tvFormatTime12h(program.fechaFin, utcOffsetSec)
end function

' Construye la ventana completa.
'
'   guide              mapa cnId → programas (de tvParseEpgGuide)
'   channels           catálogo aplanado, para sacar la url del vivo del catch-up
'   catchupVerifiedIds cn_id de los canales cuya grabación se ha SONDEADO y existe de verdad
'
' Lo de `catchupVerifiedIds` no es un lujo: el flag `catchup` lo pone un humano en la base y no se
' valida contra el servidor de vídeo, así que hay canales marcados cuya ruta no graba y daban 404 al
' pulsar el play (docs/BACKEND-GOTCHAS.md §3). Mientras la sonda no responda, el canal no cuenta.
function tvBuildEpgWindow(guide as object, channels as object, nowSec as longinteger, isCatchupClient as boolean, catchupVerifiedIds as object, utcOffsetSec = 0 as integer) as object
    empty = { cells: {}, pastColumns: 0, futureColumns: 0 }
    if channels = invalid or channels.Count() = 0 then return empty

    ' 1. Programas ordenados e índice del actual, por canal
    infos = []
    for each channel in channels
        programs = tvProgramsForChannel(guide, channel.cnId)
        infos.Push({
            channel: channel
            programs: programs
            currentIndex: tvCurrentProgramIndex(programs, nowSec)
        })
    end for

    ' 2. Cuántas columnas caben DE VERDAD (el tope es solo un máximo)
    pastColumns = 0
    futureColumns = 0
    for each info in infos
        if info.currentIndex >= 0
            if info.currentIndex > pastColumns then pastColumns = info.currentIndex
            disponibles = info.programs.Count() - 1 - info.currentIndex
        else
            disponibles = info.programs.Count()
        end if
        if disponibles > futureColumns then futureColumns = disponibles
    end for

    if pastColumns > EPG_PAST_COLUMNS() then pastColumns = EPG_PAST_COLUMNS()
    if futureColumns > EPG_FUTURE_COLUMNS() then futureColumns = EPG_FUTURE_COLUMNS()

    ' 3. Celdas por canal. Todas las filas tienen el MISMO número de columnas (las que faltan van a
    '    invalid), para que la parrilla quede alineada.
    cells = {}
    for each info in infos
        cells[tvEpgKey(info.channel.cnId)] = tvBuildEpgRow(info, pastColumns, futureColumns, nowSec, isCatchupClient, catchupVerifiedIds, utcOffsetSec)
    end for

    return { cells: cells, pastColumns: pastColumns, futureColumns: futureColumns }
end function

function tvBuildEpgRow(info as object, pastColumns as integer, futureColumns as integer, nowSec as longinteger, isCatchupClient as boolean, catchupVerifiedIds as object, utcOffsetSec as integer) as object
    row = []
    channel = info.channel

    canCatchup = isCatchupClient and channel.catchup = 1 and channel.streamUrl <> "" and tvIdInList(catchupVerifiedIds, channel.cnId)

    if info.currentIndex < 0
        ' Sin programa en emisión: las columnas pasadas quedan vacías y se muestran los primeros
        ' programas que haya. Pasa con los canales que tienen hueco en la guía.
        for i = 1 to pastColumns
            row.Push(invalid)
        end for
        for i = 0 to futureColumns
            row.Push(tvBuildEpgCell(info.programs, i, false, false, "", nowSec, utcOffsetSec))
        end for
        return row
    end if

    desde = info.currentIndex - pastColumns
    hasta = info.currentIndex + futureColumns
    for i = desde to hasta
        esAhora = (i = info.currentIndex)
        esPasado = (i < info.currentIndex)

        catchupUrl = ""
        if canCatchup and esPasado and i >= 0 and i <= info.programs.Count() - 1
            catchupUrl = tvCatchupUrlForProgram(channel.streamUrl, info.programs[i])
        end if

        row.Push(tvBuildEpgCell(info.programs, i, esAhora, esPasado, catchupUrl, nowSec, utcOffsetSec))
    end for
    return row
end function

function tvBuildEpgCell(programs as object, index as integer, esAhora as boolean, esPasado as boolean, catchupUrl as string, nowSec as longinteger, utcOffsetSec as integer) as object
    ' Fuera de rango = celda vacía. Mantiene la rejilla alineada sin inventar contenido.
    if index < 0 or index > programs.Count() - 1 then return invalid

    program = programs[index]
    progreso = 0
    if esAhora then progreso = tvPercentElapsed(program.fechaIni, program.fechaFin, nowSec)

    return {
        titulo: program.titulo
        rango: tvProgramTimeRange(program, utcOffsetSec)
        esAhora: esAhora
        esPasado: esPasado
        progreso: progreso
        catchupUrl: catchupUrl
        reproducible: catchupUrl <> ""
    }
end function

function tvEpgRowForChannel(window as object, cnId as integer) as object
    if window = invalid then return []
    key = tvEpgKey(cnId)
    if not window.cells.DoesExist(key) then return []
    return window.cells[key]
end function

function tvIdInList(ids as object, id as integer) as boolean
    if ids = invalid then return false
    for each candidate in ids
        if Int(candidate) = id then return true
    end for
    return false
end function
