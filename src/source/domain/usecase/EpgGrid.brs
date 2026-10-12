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

' ---- CU-14: la ventana VISIBLE de la parrilla --------------------------------
'
' La parrilla puede tener hasta 5 columnas, pero en pantalla solo caben 3 legibles. El resto se
' alcanza desplazando la fila en horizontal, igual que el rediseno: con las 5 metidas a la fuerza
' en el ancho disponible, cada celda queda tan estrecha que el titulo se corta a la tercera letra.
'
' Medidas tomadas del rediseno (ui/live/ChannelGrid.kt), 1 dp = 2 px:
'   margen lateral 32 dp = 64 px     columna de canal 160 dp = 320 px
'   paso de celda  = (1920 - 64*2 - 320) / 3 = 490 px
function tvEpgVisibleColumns() as integer
    return 3
end function

function tvEpgCellStride() as integer
    return 490
end function

function tvEpgChannelColumnWidth() as integer
    return 320
end function

' En reposo, la celda de AHORA se coloca en la posicion visible CENTRAL (la 1 de 0,1,2): asi se ve
' lo anterior a la izquierda y lo siguiente a la derecha de un vistazo, que es como se lee una
' parrilla de TV.
function tvEpgRestSlot() as integer
    return 1
end function

' Primera columna visible de la fila.
'
'   focusedCell = -1  -> la fila esta en reposo: se encuadra la de AHORA en la posicion central
'   focusedCell >= 0  -> se desplaza lo MINIMO para que la celda enfocada quede dentro
'
' Desplazar lo minimo (y no recentrar siempre) es lo que hace que moverse por la fila se sienta
' natural: recentrar en cada pulsacion mueve TODA la parrilla bajo el dedo del usuario.
function tvEpgFirstVisibleColumn(focusedCell as integer, nowColumn as integer, totalColumns as integer) as integer
    visibles = tvEpgVisibleColumns()
    maximo = totalColumns - visibles
    if maximo < 0 then maximo = 0

    if focusedCell < 0
        inicio = nowColumn - tvEpgRestSlot()
    else
        ' Ya esta dentro: no se mueve nada.
        inicio = focusedCell - (visibles - 1)
        if inicio < 0 then inicio = 0
        if focusedCell < inicio then inicio = focusedCell
    end if

    if inicio < 0 then inicio = 0
    if inicio > maximo then inicio = maximo
    return inicio
end function

' La misma cuenta, pero conservando el desplazamiento actual cuando la celda enfocada ya se ve.
' Es la que usa la fila: sin ella, cada movimiento del foco reencuadraria la parrilla entera.
function tvEpgScrollTo(currentFirst as integer, focusedCell as integer, nowColumn as integer, totalColumns as integer) as integer
    if focusedCell < 0 then return tvEpgFirstVisibleColumn(-1, nowColumn, totalColumns)

    visibles = tvEpgVisibleColumns()
    maximo = totalColumns - visibles
    if maximo < 0 then maximo = 0

    inicio = currentFirst
    if inicio > maximo then inicio = maximo
    if inicio < 0 then inicio = 0

    ' Se salio por la izquierda
    if focusedCell < inicio then inicio = focusedCell
    ' Se salio por la derecha
    if focusedCell > inicio + visibles - 1 then inicio = focusedCell - visibles + 1

    if inicio < 0 then inicio = 0
    if inicio > maximo then inicio = maximo
    return inicio
end function
