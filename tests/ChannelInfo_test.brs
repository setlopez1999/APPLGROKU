sub testChannelInfo()
    tvSuite("domain/usecase/ChannelInfo — CU-13, info del canal en emisión")

    r = tvFlattenCatalog(fxGetWeb2())
    canal = tvFindChannelByCnId(r.channels, 101)
    guide = tvParseEpgGuide(fxEpgGuide())
    programas = tvProgramsForChannel(guide, 101)

    base& = 1699920000
    ahora& = base& + 10 * 3600 + 30 * 60     ' 10:30, dentro de "Mañanero" (09:00-12:00)

    info = tvBuildChannelInfo(canal, programas, ahora&)
    tvAssertEqual(info.nombre, "Nativa", "nombre del canal")
    tvAssertEqual(info.numero, 1, "número del canal")
    tvAssertEqual(info.tieneAhora, true, "hay programa en emisión")
    tvAssertEqual(info.ahoraTitulo, "Mañanero", "título del programa actual")
    tvAssertEqual(info.ahoraInicio, "09:00 AM", "hora de inicio formateada")
    tvAssertEqual(info.ahoraFin, "12:00 PM", "hora de fin formateada")
    tvAssertEqual(info.progreso, 50, "la barra va por la mitad a las 10:30 de un programa 09:00-12:00")
    tvAssertEqual(info.tieneSiguiente, true, "hay programa siguiente")
    tvAssertEqual(info.siguienteTitulo, "Mediodía", "título del siguiente")

    tvSuite("ChannelInfo — sin guía (el caso NORMAL en varios ISP)")

    ' En Oneplay solo 6 de 57 canales traían guía. Esto no es el caso raro.
    sinGuia = tvBuildChannelInfo(canal, [], ahora&)
    tvAssertEqual(sinGuia.ahoraTitulo, "Programación de Nativa", "sin guía se muestra el texto de relleno")
    tvAssertEqual(sinGuia.siguienteTitulo, "Programación de Nativa", "también en el hueco del siguiente")
    tvAssertEqual(sinGuia.tieneAhora, false, "y se marca que no hay programa real")
    tvAssertEqual(sinGuia.progreso, 0, "sin programa el progreso es 0")
    tvAssertEqual(sinGuia.ahoraInicio, "", "sin programa no se inventan horarios")

    ' Último programa del día: hay actual pero no siguiente
    ultimo& = base& + 21 * 3600     ' dentro de "Nocturno" (20:00-23:00), que es el último
    alFinal = tvBuildChannelInfo(canal, programas, ultimo&)
    tvAssertEqual(alFinal.tieneAhora, true, "el último programa sí está en emisión")
    tvAssertEqual(alFinal.tieneSiguiente, false, "pero ya no hay siguiente")
    tvAssertEqual(alFinal.siguienteTitulo, "Programación de Nativa", "el hueco del siguiente usa el relleno")

    ' Canal invalid: la vista puede pedir info antes de que haya canal
    vacio = tvBuildChannelInfo(invalid, programas, ahora&)
    tvAssertEqual(vacio.nombre, "", "canal invalid devuelve un modelo vacío, no revienta")
    tvAssertEqual(vacio.tieneAhora, false, "y sin programa")
end sub
