sub testTabs()
    tvSuite("domain/usecase/Tabs — switch de marca × backend (DISENO §4)")

    ' El switch apagado es un override maestro: mande lo que mande el backend, no se dibuja
    tvAssertEqual(tvResolveOptionalTab(false, "data"), TAB_HIDDEN(), "switch apagado oculta aunque el backend traiga datos")
    tvAssertEqual(tvResolveOptionalTab(false, "off"), TAB_HIDDEN(), "switch apagado oculta siempre")
    tvAssertEqual(tvResolveOptionalTab(false, "absent"), TAB_HIDDEN(), "y también si el backend no la manda")

    tvAssertEqual(tvResolveOptionalTab(true, "data"), TAB_ENABLED(), "con switch y datos: funcional")
    tvAssertEqual(tvResolveOptionalTab(true, "off"), TAB_DISABLED(), "con switch pero apagada: se dibuja gris")
    tvAssertEqual(tvResolveOptionalTab(true, "absent"), TAB_HIDDEN(), "con switch pero ausente: no se dibuja")

    tvSuite("Tabs — la barra completa")

    marcaMinima = { tabHomeEnabled: false, tabEventsEnabled: false, tabContentEnabled: false }
    tabs = tvResolveTabs(marcaMinima, "absent", "absent")
    tvAssertEqual(tabs.live, TAB_ENABLED(), "TV en directo siempre está: es la pantalla principal")
    tvAssertEqual(tabs.home, TAB_HIDDEN(), "Inicio queda deprecado por defecto")
    tvAssertEqual(tvVisibleTabCount(tabs), 1, "con la marca mínima solo hay una pestaña visible")

    ' Con una sola pestaña no se dibuja ninguna: no aporta navegación y ensucia la barra
    tvAssertEqual(tvShouldDrawTabs(tabs), false, "una sola pestaña visible: no se dibuja la fila")

    marcaCompleta = { tabHomeEnabled: true, tabEventsEnabled: true, tabContentEnabled: true }
    completas = tvResolveTabs(marcaCompleta, "data", "off")
    tvAssertEqual(completas.home, TAB_ENABLED(), "Inicio se enciende con su switch")
    tvAssertEqual(completas.events, TAB_ENABLED(), "Eventos funcional")
    tvAssertEqual(completas.content, TAB_DISABLED(), "Contenidos gris porque el backend la manda apagada")
    tvAssertEqual(tvVisibleTabCount(completas), 4, "las cuatro visibles")
    tvAssertEqual(tvShouldDrawTabs(completas), true, "con varias sí se dibuja la fila")

    tvAssertEqual(tvStartTab(), "live", "la app arranca en TV en directo")

    tvSuite("Tabs — Contenidos según `enabledvod` del backend")

    user = UserInfoFromJson(fxGetWeb2())
    tvAssertEqual(tvContentAvailabilityFromUserInfo(user), "off", "sin enabledvod, la pestaña va apagada")

    conVod = UserInfoFromJson({ user: "x", enabledvod: true })
    tvAssertEqual(tvContentAvailabilityFromUserInfo(conVod), "data", "con enabledvod, funcional")
    tvAssertEqual(tvContentAvailabilityFromUserInfo(invalid), "absent", "sin usuario no revienta")
end sub
