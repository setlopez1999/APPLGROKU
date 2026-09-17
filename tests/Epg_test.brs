sub testEpg()
    tvSuite("domain/usecase/Epg — guía (BACKEND-GOTCHAS §7)")

    guide = tvParseEpgGuide(fxEpgGuide())
    programas = tvProgramsForChannel(guide, 101)
    tvAssertEqual(programas.Count(), 3, "se parsean los programas del canal")
    tvAssertEqual(tvProgramsForChannel(guide, 9999).Count(), 0, "canal sin guía devuelve [] recorrible")

    ' Vienen desordenados en la fixture a propósito: varios ISP no garantizan orden
    tvAssert(programas[0].fechaIni < programas[1].fechaIni, "los programas quedan ordenados por hora")
    tvAssert(programas[1].fechaIni < programas[2].fechaIni, "y el orden se mantiene hasta el final")

    ' EL CASO QUE NO SE VE EN LOS LOGS: 200 con arreglo vacío
    tvAssertEqual(tvEpgIsEmpty(tvParseEpgGuide([])), true, "guía vacía (el 200 con []) se detecta")
    tvAssertEqual(tvEpgIsEmpty(tvParseEpgGuide(invalid)), true, "guía invalid también")
    tvAssertEqual(tvEpgIsEmpty(guide), false, "guía con datos no es vacía")

    ' Guía presente pero con el array de programas vacío por canal: también cuenta como vacía
    soloCabeceras = tvParseEpgGuide([{ cn_id: 101, epg: [] }])
    tvAssertEqual(tvEpgIsEmpty(soloCabeceras), true, "canales sin programas cuentan como guía vacía")

    tvSuite("Epg — programa actual y siguiente")

    base& = 1699920000                       ' medianoche
    ahora& = base& + 10 * 3600 + 30 * 60     ' 10:30

    actual = tvCurrentProgram(programas, ahora&)
    tvAssertEqual(actual.titulo, "Mañanero", "encuentra el programa en emisión")

    siguiente = tvNextProgram(programas, actual.fechaFin)
    tvAssertEqual(siguiente.titulo, "Mediodía", "encuentra el siguiente por hora de inicio")

    ' Hueco en la guía: hay ISP con horas sin programación (aquí, entre las 14:00 y las 20:00)
    enHueco = tvCurrentProgram(programas, base& + 16 * 3600)
    tvAssertInvalid(enHueco, "sin programa que cubra ese instante devuelve invalid")

    tvAssertInvalid(tvCurrentProgram([], ahora&), "lista vacía devuelve invalid")
    tvAssertInvalid(tvCurrentProgram(invalid, ahora&), "lista invalid no revienta")
    tvAssertInvalid(tvNextProgram(programas, base& + 48 * 3600), "sin programas futuros devuelve invalid")

    tvSuite("Epg — programas de un día")

    delDia = tvProgramsForDay(programas, base&)
    tvAssertEqual(delDia.Count(), 3, "los tres programas son del mismo día")
    tvAssertEqual(tvProgramsForDay(programas, base& + 86400).Count(), 0, "ninguno es del día siguiente")
end sub
