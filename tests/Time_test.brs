sub testTime()
    tvSuite("util/Time — formato y aritmética de segundos Unix")

    medianoche& = 1699920000     ' 2023-11-14 00:00:00 UTC

    tvAssertEqual(tvFormatTime12h(medianoche&), "12:00 AM", "medianoche es 12:00 AM, no 00:00 AM")
    tvAssertEqual(tvFormatTime12h(medianoche& + 12 * 3600), "12:00 PM", "mediodía es 12:00 PM")
    tvAssertEqual(tvFormatTime12h(medianoche& + 14 * 3600 + 30 * 60), "02:30 PM", "tarde con hora de 2 dígitos")
    tvAssertEqual(tvFormatTime12h(medianoche& + 9 * 3600 + 5 * 60), "09:05 AM", "hora y minuto se rellenan con cero")
    tvAssertEqual(tvFormatTime12h(0), "", "timestamp 0 no se formatea")

    ' El desfase horario entra como parámetro: el dispositivo lo aporta, el cálculo se testea aquí.
    tvAssertEqual(tvFormatTime12h(medianoche&, -5 * 3600), "07:00 PM", "con UTC-5 la medianoche UTC es de la tarde anterior")
    tvAssertEqual(tvFormatTime24h(medianoche& + 14 * 3600 + 30 * 60), "14:30", "formato 24h para la cabecera de la parrilla")

    tvAssertEqual(tvSecondsOfDay(medianoche&), 0, "segundos del día en la medianoche")
    tvAssertEqual(tvSecondsOfDay(medianoche& + 3661), 3661, "segundos del día a la 01:01:01")
    tvAssertEqual(tvStartOfDay(medianoche& + 50000), medianoche&, "el inicio del día recorta la hora")
    tvAssertEqual(tvIsSameDay(medianoche& + 100, medianoche& + 80000), true, "dos instantes del mismo día")
    tvAssertEqual(tvIsSameDay(medianoche& + 100, medianoche& + 90000), false, "instantes de días distintos")

    tvSuite("util/Time — progreso del programa (barra del footer)")

    tvAssertEqual(tvPercentElapsed(100, 200, 150), 50, "mitad del programa es 50%")
    tvAssertEqual(tvPercentElapsed(100, 200, 100), 0, "justo al empezar es 0%")
    tvAssertEqual(tvPercentElapsed(100, 200, 200), 100, "justo al acabar es 100%")
    tvAssertEqual(tvPercentElapsed(100, 200, 50), 0, "antes de empezar no da negativo")
    tvAssertEqual(tvPercentElapsed(100, 200, 5000), 100, "después de acabar no pasa de 100")
    tvAssertEqual(tvPercentElapsed(100, 100, 100), 0, "programa de duración cero no divide por cero")
    tvAssertEqual(tvPercentElapsed(200, 100, 150), 0, "fin antes que inicio no revienta")

    tvAssertEqual(tvIsWithinRange(100, 200, 150), true, "instante dentro del rango")
    tvAssertEqual(tvIsWithinRange(100, 200, 250), false, "instante fuera del rango")
end sub
