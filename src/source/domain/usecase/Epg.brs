' CU-10 — Guía de programación.
'
' Hay DOS fuentes de EPG y no son la misma (docs/BACKEND-GOTCHAS.md §7):
'   - `epg[]` dentro de get-web2  → suele venir casi vacío (6 de 57 canales en Oneplay)
'   - api/get-epgguide            → la guía completa, y es la que alimenta la parrilla
'
' Y la trampa fina: get-epgguide puede devolver HTTP 200 con un arreglo VACÍO (2 bytes). No es un
' error que se vea en logs ni en códigos de estado: la parrilla queda vacía y parece un bug de la
' app. Por eso existe `tvEpgIsEmpty` — si la guía viene vacía hay que REINTENTAR ese endpoint por su
' cuenta, aunque la lista de canales no haya cambiado.

' get-epgguide → mapa cnId (como texto) → lista de programas ordenada por hora de inicio.
function tvParseEpgGuide(json as object) as object
    guide = {}
    if json = invalid then return guide
    if type(json) <> "roArray" then return guide

    for each entry in json
        cnId = jsonInt(entry, "cn_id")
        if cnId > 0
            programs = EpgListFromJson(jsonArray(entry, "epg"))
            guide[tvEpgKey(cnId)] = tvSortProgramsByStart(programs)
        end if
    end for
    return guide
end function

' El 200-con-[] que no se ve en los logs.
function tvEpgIsEmpty(guide as object) as boolean
    if guide = invalid then return true
    total = 0
    for each key in guide
        total = total + guide[key].Count()
    end for
    return total = 0
end function

function tvEpgKey(cnId as integer) as string
    return Str(cnId).Trim()
end function

function tvProgramsForChannel(guide as object, cnId as integer) as object
    if guide = invalid then return []
    key = tvEpgKey(cnId)
    if not guide.DoesExist(key) then return []
    return guide[key]
end function

' Programa en emisión ahora mismo, o invalid si no hay ninguno que cubra este instante (hay huecos
' en la guía de varios ISP).
function tvCurrentProgram(programs as object, nowSec as longinteger) as object
    if programs = invalid then return invalid
    for each program in programs
        if tvIsWithinRange(program.fechaIni, program.fechaFin, nowSec) then return program
    end for
    return invalid
end function

' El siguiente por hora de inicio. No se asume que sea el de la posición +1: si hay un hueco o la
' guía viene desordenada, "el siguiente del array" no es "el siguiente en el tiempo".
function tvNextProgram(programs as object, afterSec as longinteger) as object
    if programs = invalid then return invalid
    best = invalid
    for each program in programs
        if program.fechaIni >= afterSec
            if best = invalid or program.fechaIni < best.fechaIni then best = program
        end if
    end for
    return best
end function

' Ordenación por inserción. Las listas por canal son de decenas de programas, no miles.
' Nota: `roArray` NO tiene `Insert()` — solo Push/Pop/Shift/Unshift/Delete —, así que el hueco se
' abre desplazando por índice.
function tvSortProgramsByStart(programs as object) as object
    if programs = invalid then return []

    sorted = []
    for each program in programs
        sorted.Push(program)
    end for

    for i = 1 to sorted.Count() - 1
        current = sorted[i]
        j = i - 1
        while j >= 0 and sorted[j].fechaIni > current.fechaIni
            sorted[j + 1] = sorted[j]
            j = j - 1
        end while
        sorted[j + 1] = current
    end for

    return sorted
end function

' Programas de un día concreto, para la parrilla (el original filtra por día, player.js:filterPrograms).
function tvProgramsForDay(programs as object, daySec as longinteger, utcOffsetSec = 0 as integer) as object
    out = []
    if programs = invalid then return out
    for each program in programs
        if tvIsSameDay(program.fechaIni, daySec, utcOffsetSec) then out.Push(program)
    end for
    return out
end function
