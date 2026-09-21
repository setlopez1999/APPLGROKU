' Ejecuta los tests de la capa de lógica en Node, sin Roku:
'   npm run test
'
' Solo cubre `domain/` y `data/` puros. Lo que toca el dispositivo (red, registro, vídeo, foco) se
' verifica en el Roku real — ver docs/PLAN.md §9.

sub main()
    print ""
    print "  TV-Visor Roku — tests de lógica"

    tvTestInit()

    testJson()
    testTime()
    testModels()
    testApiRoutes()
    testFlattenCatalog()
    testChannelAccess()
    testZapping()
    testEpg()
    testChannelInfo()
    testCatchup()
    testCatalogRefresh()
    testFavorites()
    testNotifications()
    testSessionRules()
    testPlayback()
    testTabs()
    testParentalPin()
    testEpgGrid()

    code = tvTestExitCode()
    if code <> 0 then throw "Hay tests en rojo"
end sub
