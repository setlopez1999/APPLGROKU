sub testNotifications()
    tvSuite("domain/usecase/Notifications — CU-19 y CU-20")

    lista = tvParseNotifications(fxNotifications())
    tvAssertEqual(lista.Count(), 3, "se parsean las tres notificaciones")

    ' El original invierte la lista para dejar las más nuevas primero
    tvAssertEqual(lista[0].texto, "La más nueva", "la más nueva queda primero")
    tvAssertEqual(lista[2].texto, "La más vieja", "y la más vieja al final")

    tvAssertEqual(tvParseNotifications({}).Count(), 0, "respuesta sin `message` devuelve []")
    tvAssertEqual(tvParseNotifications(invalid).Count(), 0, "respuesta invalid no revienta")
    tvAssertEqual(tvParseNotifications({ message: "roto" }).Count(), 0, "`message` con forma rara tampoco")

    tvSuite("Notifications — NO LEÍDA y NUEVA no son lo mismo")

    tvAssertEqual(tvCountUnread(lista), 2, "hay dos sin leer")
    tvAssertEqual(tvUnreadIds(lista).Count(), 2, "y dos ids que marcar como leídas")
    tvAssertEqual(tvUnreadIds(lista)[0], "3", "empezando por la más nueva")

    ' Sin marca previa: todas las no leídas son nuevas
    tvAssertEqual(tvCountNew(lista, ""), 2, "sin marca previa, las no leídas son nuevas")

    ' Con marca: solo cuenta lo posterior a ella
    tvAssertEqual(tvCountNew(lista, "2026-09-16 10:00:00"), 1, "con marca previa solo cuenta lo posterior")
    tvAssertEqual(tvCountNew(lista, "2026-09-99 00:00:00"), 0, "con una marca más reciente que todo, ninguna es nueva")

    tvSuite("Notifications — texto del aviso flotante")

    ' Este es el caso que evita que el aviso vuelva a saltar cada 60 segundos
    tvAssertEqual(tvNotificationAlertText(lista, "2026-09-99 00:00:00"), "", "sin nuevas no se avisa, aunque queden sin leer")

    tvAssertEqual(tvNotificationAlertText(lista, ""), "Tienes 2 notificaciones nuevas", "varias nuevas: mensaje agrupado")

    unaSola = tvNotificationAlertText(lista, "2026-09-16 10:00:00")
    tvAssertEqual(unaSola, "La más nueva", "una sola nueva: se muestra su texto, tomado de la PRIMERA no leída")

    tvAssertEqual(tvNotificationAlertText([], ""), "", "lista vacía no avisa")
    tvAssertEqual(tvNotificationAlertText(invalid, ""), "", "lista invalid no revienta")

    tvSuite("Notifications — marca para no repetir el aviso")

    tvAssertEqual(tvLatestCreatedAt(lista), "2026-09-17 09:00:00", "la marca es la fecha más reciente")
    tvAssertEqual(tvLatestCreatedAt([]), "", "lista vacía no deja marca")
end sub
