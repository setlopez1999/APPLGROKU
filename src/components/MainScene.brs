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

    m.heartbeatTimer = m.top.findNode("heartbeatTimer")
    m.heartbeatTimer.observeField("fire", "onHeartbeat")
    m.revalidateTimer = m.top.findNode("revalidateTimer")
    m.revalidateTimer.observeField("fire", "onRevalidate")
    m.catalogSignature = ""

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

    m.catalogSignature = tvCatalogSignature(catalog.channels)
    m.heartbeatTimer.control = "start"
    m.revalidateTimer.control = "start"
end sub

sub onLogout()
    ' En Roku NO hay cancelacion automatica: si no se paran a mano, los temporizadores
    ' seguirian pidiendo con un token muerto. Es el equivalente de los intervals apilados
    ' del original (CU-19).
    m.heartbeatTimer.control = "stop"
    m.revalidateTimer.control = "stop"
    m.catalogSignature = ""

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

' ---- CU-16: heartbeat al dashboard (cada 15 s) -------------------------------
'
' Fire-and-forget, igual que el original: sin callback y sin manejo de error.

sub onHeartbeat()
    userInfo = m.global.session
    if not tvHasSession(userInfo) then return

    cnId = m.global.currentCnId
    channel = tvFindChannelByCnId(m.global.channels, cnId)
    reproduciendo = (m.videoPlayer.state = "playing")

    if not tvShouldSendHeartbeat(reproduciendo, m.global.isOnline, false, channel, userInfo.token) then return

    m.heartbeatTask = CreateObject("roSGNode", "ApiTask")
    m.heartbeatTask.request = tvApiRequest(tvApiDashboardUrl(m.brand.baseUrl, userInfo.token, cnId), "GET")
    m.heartbeatTask.control = "RUN"
end sub

' ---- CU-17: revalidacion de sesion (cada 60 s) --------------------------------

sub onRevalidate()
    userInfo = m.global.session
    if not tvHasSession(userInfo) then return

    ' El backend exige el password EN CLARO en cada get-web2, no solo en el login
    ' (docs/BACKEND-GOTCHAS.md 11). Por eso se guarda cifrado toda la sesion.
    password = tvSessionPassword()
    if password = "" then return

    url = tvApiGetWeb2Url(m.brand.baseUrl, userInfo.userEmail, password, tvSessionDeviceId(), m.brand.platform, userInfo.token)

    m.revalidateTask = CreateObject("roSGNode", "ApiTask")
    m.revalidateTask.observeField("response", "onRevalidateResponse")
    m.revalidateTask.request = tvApiRequest(url)
    m.revalidateTask.control = "RUN"
end sub

sub onRevalidateResponse()
    response = m.revalidateTask.response

    ' Un fallo de red NO cierra la sesion: el backend tiene hipos, y echar al usuario por uno seria
    ' peor que esperar al siguiente ciclo.
    if not response.ok then return
    if response.json = invalid then return

    ' Esto si: el backend dice que el token ya no vale.
    if ResponseHasError(response.json)
        print "[TV] revalidacion: sesion rechazada, cerrando"
        onLogout()
        return
    end if

    m.global.session = UserInfoFromJson(response.json)
    catalog = tvFlattenCatalog(response.json)

    ' RECONSTRUIR SOLO SI ALGO CAMBIO DE VERDAD (docs/BACKEND-GOTCHAS.md 6): redibujar el catalogo
    ' cada 60 s interrumpiria la reproduccion y moveria el foco mientras el usuario navega.
    if not tvCatalogChanged(m.catalogSignature, catalog.channels) then return

    print "[TV] revalidacion: el catalogo cambio ("; catalog.channels.Count(); " canales)"
    m.catalogSignature = tvCatalogSignature(catalog.channels)
    m.global.channels = catalog.channels
    m.global.sections = catalog.sections

    if m.mainScreen <> invalid then m.mainScreen.catalogVersion = m.mainScreen.catalogVersion + 1
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
