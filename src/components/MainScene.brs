' Escena raíz: pila de pantallas y botón Atrás. Ver docs/arquitectura_flujo.md §1 y §4.
'
' ⚠ Toca el dispositivo: no se ejecuta en `npm test`. Solo la valida el compilador.
'
' Nota (verificada): lo que hay en `pkg:/source/` NO está disponible aquí por arte de magia. Cada
' componente declara con <script> lo que usa, en su .xml (docs/ROKU-GOTCHAS.md §16).

sub init()
    print "[TV] MainScene.init"
    m.brand = m.global.brand

    ' El truco de siempre: sin vaciar backgroundURI, backgroundColor no se aplica.
    m.top.backgroundURI = ""
    m.top.backgroundColor = m.brand.background

    m.background = m.top.findNode("background")
    m.background.color = m.brand.background

    m.screenStack = m.top.findNode("screenStack")
    m.modalLayer = m.top.findNode("modalLayer")

    ' Se crea una vez y se PRESTA a las pantallas que lo necesiten. Nadie crea otro.
    m.videoPlayer = m.top.findNode("videoPlayer")

    m.stack = []

    showLogin()
end sub

' ---- pila de pantallas -------------------------------------------------------

sub pushScreen(node as object, hidePrevious = false as boolean)
    ' Pantalla completa OCULTA la de debajo: si no, los overlays de "TV en directo" se verían
    ' encima del vídeo, porque esta pantalla no lleva fondo propio. Los modales, en cambio, tienen
    ' que dejar ver lo que hay detrás.
    if hidePrevious and m.stack.Count() > 0
        m.stack[m.stack.Count() - 1].visible = false
    end if

    m.screenStack.appendChild(node)
    m.stack.Push(node)
    node.setFocus(true)
end sub

sub popScreen()
    ' La primera pantalla no se saca: si no, quedaría la pila vacía y sin foco.
    if m.stack.Count() <= 1 then return

    top = m.stack.Pop()
    m.screenStack.removeChild(top)

    debajo = m.stack[m.stack.Count() - 1]
    debajo.visible = true
    debajo.setFocus(true)
end sub

' Reemplaza la pila entera (login → main, y al revés en el logout).
sub replaceStack(node as object)
    for each screen in m.stack
        m.screenStack.removeChild(screen)
    end for
    m.stack = []
    pushScreen(node)
end sub

' ---- pantallas ---------------------------------------------------------------

sub showLogin()
    login = CreateObject("roSGNode", "LoginScreen")
    login.observeField("session", "onLoginSuccess")
    replaceStack(login)
end sub

sub onLoginSuccess()
    session = m.stack[m.stack.Count() - 1].session
    if session = invalid then return

    ' El estado de sesión vive en el nodo global: cualquier pantalla lo observa desde ahí, nadie se
    ' lo pasa a nadie (docs/arquitectura_flujo.md §3).
    m.global.session = session.userInfo
    m.global.isLoggedIn = true

    catalog = tvFlattenCatalog(session.raw)
    m.global.channels = catalog.channels
    m.global.sections = catalog.sections

    print "[TV] catalogo: "; catalog.channels.Count(); " canales reproducibles en "; catalog.sections.Count(); " categorias"

    main = CreateObject("roSGNode", "MainScreen")
    main.videoNode = m.videoPlayer
    main.observeField("logout", "onLogout")
    main.observeField("fullscreenCnId", "onRequestFullscreen")
    m.mainScreen = main
    replaceStack(main)
end sub

sub onLogout()
    ' Detener, no pausar: pausar deja el decodificador reservado (BACKEND-GOTCHAS §9).
    m.videoPlayer.control = "stop"
    m.videoPlayer.visible = false

    tvSessionClear()
    m.global.session = {}
    m.global.isLoggedIn = false
    m.global.channels = []
    m.global.sections = []
    showLogin()
end sub

' ---- pantalla completa -------------------------------------------------------

sub onRequestFullscreen()
    player = CreateObject("roSGNode", "FullscreenPlayer")
    player.videoNode = m.videoPlayer
    m.fullscreenPlayer = player

    pushScreen(player, true)

    ' El canal se pone DESPUÉS de apilar: al asignarlo se dispara onStartChannel, que ya necesita
    ' el nodo Video puesto y la pantalla en el árbol.
    player.startCnId = m.mainScreen.fullscreenCnId
end sub

' Al salir, "TV en directo" tiene que quedarse en el canal al que se haya zapeado.
sub syncAfterFullscreen()
    if m.fullscreenPlayer = invalid then return
    if m.mainScreen = invalid then return

    cnId = m.fullscreenPlayer.currentCnId
    m.fullscreenPlayer = invalid
    if cnId > 0 then m.mainScreen.resumeCnId = cnId
end sub

' ---- botón Atrás -------------------------------------------------------------

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if key = "back"
        ' Prioridad (docs/plan_migracion.md §6): modal → pantalla completa → EPG → pantalla apilada
        ' → pestaña inicial → cerrar el canal. Los primeros niveles los resuelve cada pantalla y solo
        ' llega aquí lo que nadie ha consumido.
        if m.stack.Count() > 1
            popScreen()
            syncAfterFullscreen()
            return true
        end if

        ' En la raíz se devuelve false y el sistema cierra el canal. En Roku no hay "salir de la app"
        ' propio y no conviene inventar un diálogo de confirmación (docs/ROKU-GOTCHAS.md §7).
        return false
    end if

    return false
end function
