sub testCatchup()
    tvSuite("domain/usecase/Catchup — url del DVR (BACKEND-GOTCHAS §2, §3, §4)")

    vivo = "https://h:1936/transcoderip/nativa.stream/playlist.m3u8"

    tvAssertEqual(tvCatchupUrl(vivo, 1700000000, 3600), "https://h:1936/transcoderip/nativa.stream/playlist_dvr_range-1700000000-3600.m3u8", "inserta _dvr_range ANTES del .m3u8")

    ' Bordes de la fórmula
    tvAssertEqual(tvCatchupUrl("", 1700000000, 3600), "", "url de vivo vacía devuelve vacío")
    tvAssertEqual(tvCatchupUrl(vivo, 1700000000, 0), "", "duración 0 no produce url")
    tvAssertEqual(tvCatchupUrl(vivo, 1700000000, -5), "", "duración negativa tampoco")
    tvAssertEqual(tvCatchupUrl("https://h:1936/dir/canal.stream/playlist", 1700000000, 600), "https://h:1936/dir/canal.stream/playlist_dvr_range-1700000000-600.m3u8", "url sin .m3u8: se añade igualmente")

    ' Desde un programa del EPG: la duración sale de fecha_fin - fecha_ini (ambos en SEGUNDOS)
    programa = EpgProgramFromJson({ titulo: "Noticias", fecha_ini: 1700000000, fecha_fin: 1700003600 })
    tvAssertEqual(tvCatchupUrlForProgram(vivo, programa), "https://h:1936/transcoderip/nativa.stream/playlist_dvr_range-1700000000-3600.m3u8", "url del programa con su duración calculada")
    tvAssertEqual(tvCatchupUrlForProgram(vivo, invalid), "", "programa invalid devuelve vacío")

    tvSuite("Catchup — cuándo se OFRECE (el flag miente, §3)")

    r = tvFlattenCatalog(fxGetWeb2())
    conCatchup = tvFindChannelByCnId(r.channels, 101)      ' catchup: 1
    sinCatchup = tvFindChannelByCnId(r.channels, 501)      ' sin campo catchup → 0
    ahora = 1700010000

    pasado = EpgProgramFromJson({ titulo: "Ya terminó", fecha_ini: 1700000000, fecha_fin: 1700003600 })
    actual = EpgProgramFromJson({ titulo: "Ahora", fecha_ini: 1700009000, fecha_fin: 1700012600 })

    tvAssertEqual(tvCatchupIsOffered(true, conCatchup, pasado, ahora), true, "programa terminado + canal con catchup: se ofrece")
    tvAssertEqual(tvCatchupIsOffered(true, conCatchup, actual, ahora), false, "el programa en emisión se ve en vivo, no como grabación")
    tvAssertEqual(tvCatchupIsOffered(true, sinCatchup, pasado, ahora), false, "canal sin catchup no se ofrece")
    tvAssertEqual(tvCatchupIsOffered(false, conCatchup, pasado, ahora), false, "ISP que no es cliente de catch-up: nunca")
    tvAssertEqual(tvCatchupIsOffered(true, invalid, pasado, ahora), false, "canal invalid no revienta")
    tvAssertEqual(tvCatchupIsOffered(true, conCatchup, invalid, ahora), false, "programa invalid no revienta")

    tvSuite("Catchup — CU-15 el salto de avance y retroceso")

    ' Una dieciseisava parte de la duración, NO un número fijo de segundos: un salto de 10 s es
    ' inútil en una película y uno de 5 min se pasa de largo en un noticiero.
    tvAssertEqual(tvCatchupSeekStepSec(3600), 225, "en una grabación de 1 h el salto es de 3:45")
    tvAssertEqual(tvCatchupSeekStepSec(1200), 75, "en una de 20 min, 1:15")
    tvAssertEqual(tvCatchupSeekStepSec(10800), 675, "en una de 3 h, 11:15")

    ' En una grabación muy corta el botón tiene que hacer algo perceptible igualmente.
    tvAssertEqual(tvCatchupSeekStepSec(60), 10, "en una muy corta, el mínimo de 10 s")
    tvAssertEqual(tvCatchupSeekStepSec(0), 10, "sin duración conocida, 10 s")

    tvSuite("Catchup — el salto se acota a la grabación")

    ' Sin acotar, Roku rechaza el seek fuera de rango y el botón no hace nada.
    tvAssertEqual(tvCatchupSeekTarget(100, 225, true, 3600), 325, "avanzar suma el paso")
    tvAssertEqual(tvCatchupSeekTarget(300, 225, false, 3600), 75, "retroceder lo resta")
    tvAssertEqual(tvCatchupSeekTarget(100, 225, false, 3600), 0, "no se retrocede por debajo de 0")
    tvAssertEqual(tvCatchupSeekTarget(3500, 225, true, 3600), 3600, "no se avanza más allá del final")
    tvAssertEqual(tvCatchupSeekTarget(100, 225, true, 0), 325, "sin duración conocida no se acota por arriba")
end sub
