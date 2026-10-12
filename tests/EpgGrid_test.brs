sub testEpgGrid()
    tvSuite("domain/usecase/EpgGrid — ventana de la parrilla (DISENO §2.4)")

    r = tvFlattenCatalog(fxGetWeb2())
    guide = tvParseEpgGuide(fxEpgGuide())
    base& = 1699920000
    ahora& = base& + 13 * 3600     ' 13:00 → dentro de "Mediodía" (12:00-14:00), el 2º programa

    window = tvBuildEpgWindow(guide, r.channels, ahora&, false, [])

    ' El canal 101 tiene 3 programas y está en el segundo: 1 pasado disponible, 1 futuro
    tvAssertEqual(window.pastColumns, 1, "las columnas pasadas se ajustan a lo que hay, no al tope")
    tvAssertEqual(window.futureColumns, 1, "y las futuras igual")

    fila = tvEpgRowForChannel(window, 101)
    tvAssertEqual(fila.Count(), 3, "la fila tiene pasadas + ahora + futuras")
    tvAssertEqual(fila[0].titulo, "Mañanero", "la primera celda es el programa pasado")
    tvAssertEqual(fila[0].esPasado, true, "y está marcada como pasada")
    tvAssertEqual(fila[1].titulo, "Mediodía", "la del medio es la que está en emisión")
    tvAssertEqual(fila[1].esAhora, true, "y está marcada como AHORA")
    tvAssertEqual(fila[1].progreso, 50, "con su progreso a la mitad (13:00 de 12:00-14:00)")
    tvAssertEqual(fila[2].titulo, "Nocturno", "la última es la futura")
    tvAssertEqual(fila[2].esAhora, false, "que no es AHORA")
    tvAssertEqual(fila[0].rango, "09:00 AM - 12:00 PM", "el rango horario se formatea")

    tvSuite("EpgGrid — todas las filas alineadas")

    ' El canal 102 solo tiene un programa, y ya terminó: su fila debe tener el MISMO ancho, con
    ' celdas vacías donde no hay nada. Si no, la rejilla se descuadra.
    fila102 = tvEpgRowForChannel(window, 102)
    tvAssertEqual(fila102.Count(), 3, "un canal con menos programas tiene la fila igual de ancha")
    tvAssertInvalid(fila102[0], "y las columnas que le faltan van vacías")

    ' Un canal sin guía ninguna
    filaSinGuia = tvEpgRowForChannel(window, 301)
    tvAssertEqual(filaSinGuia.Count(), 3, "un canal sin guía también mantiene el ancho")

    tvSuite("EpgGrid — sin datos pasados no se dibujan columnas pasadas")

    ' A las 10:30 el canal 101 está en su PRIMER programa: no hay nada pasado que mostrar.
    temprano& = base& + 10 * 3600 + 30 * 60
    ventanaTemprana = tvBuildEpgWindow(guide, r.channels, temprano&, false, [])
    tvAssertEqual(ventanaTemprana.pastColumns, 0, "sin programas pasados, cero columnas pasadas")

    filaTemprana = tvEpgRowForChannel(ventanaTemprana, 101)
    tvAssertEqual(filaTemprana.Count(), 2, "la fila se encoge: solo AHORA y la siguiente")
    tvAssertEqual(filaTemprana[0].esAhora, true, "empieza directamente por la de AHORA")

    tvSuite("EpgGrid — catch-up: el flag no basta, hace falta la sonda")

    ' El canal 101 viene con catchup=1 en la respuesta del backend
    sinSonda = tvBuildEpgWindow(guide, r.channels, ahora&, true, [])
    tvAssertEqual(tvEpgRowForChannel(sinSonda, 101)[0].reproducible, false, "con catchup=1 pero sin sondear, NO se ofrece")

    conSonda = tvBuildEpgWindow(guide, r.channels, ahora&, true, [101])
    celda = tvEpgRowForChannel(conSonda, 101)[0]
    tvAssertEqual(celda.reproducible, true, "sondeado y confirmado: sí se ofrece")
    tvAssert(Instr(1, celda.catchupUrl, "_dvr_range-") > 0, "y trae la url del DVR construida")

    ' El ISP que no es cliente de catch-up nunca lo ofrece, aunque el canal esté sondeado
    apagado = tvBuildEpgWindow(guide, r.channels, ahora&, false, [101])
    tvAssertEqual(tvEpgRowForChannel(apagado, 101)[0].reproducible, false, "ISP sin catch-up: nunca")

    ' La celda de AHORA nunca es catch-up: eso se ve en vivo
    tvAssertEqual(tvEpgRowForChannel(conSonda, 101)[1].reproducible, false, "la celda de AHORA no se ofrece como grabación")

    tvSuite("EpgGrid — bordes")

    vacio = tvBuildEpgWindow(guide, [], ahora&, false, [])
    tvAssertEqual(vacio.pastColumns, 0, "sin canales no hay ventana")
    tvAssertEqual(tvBuildEpgWindow(guide, invalid, ahora&, false, []).pastColumns, 0, "canales invalid no revienta")

    ' Guía vacía: el 200-con-[] del §7. Las filas existen pero sin contenido.
    sinGuia = tvBuildEpgWindow({}, r.channels, ahora&, false, [])
    tvAssertEqual(tvEpgRowForChannel(sinGuia, 101).Count(), 1, "sin guía queda una sola columna vacía")

    tvAssertEqual(tvCurrentProgramIndex(invalid, ahora&), -1, "índice del actual con lista invalid")
    tvAssertEqual(tvProgramTimeRange(invalid), "", "rango de un programa invalid")

    tvSuite("EpgGrid — CU-14 la ventana visible y el desplazamiento")

    ' Con las 5 columnas metidas a la fuerza en el ancho, el título se corta a la tercera letra.
    tvAssertEqual(tvEpgVisibleColumns(), 3, "solo 3 columnas caben legibles")
    tvAssertEqual(tvEpgCellStride(), 490, "paso de celda del rediseño (1920-128-320)/3")
    tvAssertEqual(tvEpgChannelColumnWidth(), 320, "columna del canal, 160 dp del rediseño")
    tvAssertEqual(tvEpgRestSlot(), 1, "en reposo, AHORA va en la posición central")

    tvSuite("EpgGrid — encuadre en reposo")

    ' Con 5 columnas y AHORA en la 3: se ve la 2, la 3 y la 4.
    tvAssertEqual(tvEpgFirstVisibleColumn(-1, 3, 5), 2, "AHORA queda en la posición central")

    ' Si AHORA es la primera, no se puede desplazar a la izquierda de cero.
    tvAssertEqual(tvEpgFirstVisibleColumn(-1, 0, 5), 0, "no se desplaza por debajo de la primera")

    ' Ni más allá del final: con 5 columnas el máximo arranque es la 2.
    tvAssertEqual(tvEpgFirstVisibleColumn(-1, 4, 5), 2, "no se desplaza más allá del final")

    ' Menos columnas que posiciones visibles: todo a la vista, sin desplazar.
    tvAssertEqual(tvEpgFirstVisibleColumn(-1, 1, 2), 0, "si caben todas, no se desplaza")

    tvSuite("EpgGrid — desplazamiento mínimo al mover el foco")

    ' Recentrar en cada pulsación movería TODA la parrilla bajo el dedo del usuario.
    tvAssertEqual(tvEpgScrollTo(2, 3, 3, 5), 2, "si la celda enfocada ya se ve, no se mueve nada")
    tvAssertEqual(tvEpgScrollTo(2, 2, 3, 5), 2, "el borde izquierdo visible tampoco mueve")
    tvAssertEqual(tvEpgScrollTo(2, 4, 3, 5), 2, "el borde derecho visible tampoco mueve")

    ' Salirse por un lado desplaza exactamente una columna, no más.
    tvAssertEqual(tvEpgScrollTo(2, 1, 3, 5), 1, "salirse por la izquierda desplaza una columna")
    tvAssertEqual(tvEpgScrollTo(0, 3, 3, 5), 1, "salirse por la derecha desplaza una columna")

    ' Y nunca fuera de rango.
    tvAssertEqual(tvEpgScrollTo(0, 4, 3, 5), 2, "la última columna encuadra en el tope")
    tvAssertEqual(tvEpgScrollTo(9, 0, 3, 5), 0, "un desplazamiento imposible se acota")
    tvAssertEqual(tvEpgScrollTo(0, -1, 3, 5), 2, "sin celda enfocada se vuelve al encuadre de reposo")
end sub
