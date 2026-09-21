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

sub pushScreen(node as object)
    m.screenStack.appendChild(node)
    m.stack.Push(node)
    node.setFocus(true)
end sub

sub popScreen()
    ' La primera pantalla no se saca: si no, quedaría la pila vacía y sin foco.
    if m.stack.Count() <= 1 then return

    top = m.stack.Pop()
    m.screenStack.removeChild(top)
    m.stack[m.stack.Count() - 1].setFocus(true)
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

    main = CreateObject("roSGNode", "MainScreen")
    main.videoNode = m.videoPlayer
    main.observeField("logout", "onLogout")
    replaceStack(main)
end sub

sub onLogout()
    ' Detener, no pausar: pausar deja el decodificador reservado (BACKEND-GOTCHAS §9).
    m.videoPlayer.control = "stop"
    m.videoPlayer.visible = false

    tvSessionClear()
    m.global.session = invalid
    m.global.isLoggedIn = false
    m.global.channels = []
    m.global.sections = []
    showLogin()
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
            return true
        end if

        ' En la raíz se devuelve false y el sistema cierra el canal. En Roku no hay "salir de la app"
        ' propio y no conviene inventar un diálogo de confirmación (docs/ROKU-GOTCHAS.md §7).
        return false
    end if

    return false
end function
