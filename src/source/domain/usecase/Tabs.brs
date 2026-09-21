' Pestañas de la barra superior. Réplica de TabsResolver.kt del rediseño (ver docs/DISENO.md §4).
'
' Una pestaña opcional (Eventos, Contenidos) depende de DOS cosas a la vez: el switch de marca del
' ISP y lo que mande el backend. El switch es un override maestro: si está apagado, la pestaña no se
' dibuja mande lo que mande el backend.

' Estados de dibujado
function TAB_HIDDEN() as string
    return "hidden"
end function

function TAB_DISABLED() as string
    return "disabled"
end function

function TAB_ENABLED() as string
    return "enabled"
end function

' Qué manda el backend para una pestaña opcional:
'   "data"    viene y trae contenido
'   "off"     viene pero vacía / apagada
'   "absent"  no la manda
function tvResolveOptionalTab(envSwitch as boolean, backend as string) as string
    if not envSwitch then return TAB_HIDDEN()
    if backend = "data" then return TAB_ENABLED()
    if backend = "off" then return TAB_DISABLED()
    return TAB_HIDDEN()
end function

' Estado de las cuatro pestañas de la barra.
' "TV en directo" es la única que SIEMPRE está: es la pantalla principal de la app.
function tvResolveTabs(brand as object, eventsBackend as string, contentBackend as string) as object
    home = TAB_HIDDEN()
    if brand.tabHomeEnabled then home = TAB_ENABLED()

    return {
        home: home
        live: TAB_ENABLED()
        events: tvResolveOptionalTab(brand.tabEventsEnabled, eventsBackend)
        content: tvResolveOptionalTab(brand.tabContentEnabled, contentBackend)
    }
end function

' Cuántas se dibujan. Con UNA sola visible no se dibuja ninguna: una pestaña suelta no aporta
' navegación y ensucia la barra (misma decisión que en el rediseño Kotlin).
function tvVisibleTabCount(tabs as object) as integer
    count = 0
    for each key in ["home", "live", "events", "content"]
        if tabs[key] <> TAB_HIDDEN() then count = count + 1
    end for
    return count
end function

function tvShouldDrawTabs(tabs as object) as boolean
    return tvVisibleTabCount(tabs) > 1
end function

' Pestaña de arranque: "TV en directo" (Inicio quedó deprecado).
function tvStartTab() as string
    return "live"
end function

' `enabledvod` del backend decide si hay pestaña de Contenidos.
function tvContentAvailabilityFromUserInfo(userInfo as object) as string
    ' Comprobación en línea, sin llamar a otro archivo: con los <script> explícitos de SceneGraph,
    ' cada dependencia cruzada obliga a añadir includes en todos los componentes que la arrastren
    ' (docs/ROKU-GOTCHAS.md §16). Los archivos de `domain/` se mantienen autocontenidos.
    if userInfo = invalid then return "absent"
    if type(userInfo) <> "roAssociativeArray" then return "absent"
    if not userInfo.DoesExist("enabledVod") then return "absent"
    if userInfo.enabledVod then return "data"
    return "off"
end function
