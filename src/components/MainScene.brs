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

    m.networkTimer = m.top.findNode("networkTimer")
    m.networkTimer.observeField("fire", "onNetworkCheck")
    m.networkTimer.control = "start"

    m.appModal = m.top.findNode("appModal")
    m.appModal.observeField("action", "onModalAction")
    m.modalKind = ""

    m.pinModal = m.top.findNode("pinModal")
    m.pinModal.observeField("action", "onPinAction")

    ' CU-25: instante del ultimo ATRAS en la raiz. 0 = no hay ninguno pendiente.
    m.lastBackMs = 0&
    m.toast = m.top.findNode("toast")
    m.toast.color = m.brand.textPrimary
    m.toastBg = m.top.findNode("toastBg")
    m.toastBg.color = m.brand.surface
    m.toastTimer = m.top.findNode("toastTimer")
    m.toastTimer.observeField("fire", "onToastTimer")

    ' Certificacion 5.1/5.2 — el enlace profundo del ARRANQUE EN FRIO ya esta puesto: main.brs lo
    ' deja en el nodo global ANTES de crear esta escena. Se guarda y lo aplica `enterApp`, que es
    ' el unico momento en que existe un catalogo contra el que resolverlo.
    m.pendingDeepLink = invalid
    rememberDeepLink(m.global.deepLink)

    ' Y el de la app YA ABIERTA, que main.brs recoge por roInput y deja en el mismo sitio.
    m.global.observeField("deepLink", "onDeepLink")

    bootstrap()
end sub

' ---- certificacion 5.1/5.2: enlaces profundos --------------------------------
'
' La regla de oro es la que prueba el revisor de Roku: UN ENLACE QUE NO SIRVE NO PUEDE DEJAR LA APP
' EN BLANCO. Pase lo que pase se arranca normal; como mucho se avisa.
'
' Hay dos momentos muy distintos y por eso hay dos caminos:
'
'   app cerrada  el enlace llega ANTES que la sesion y el catalogo. No hay nada contra lo que
'                resolverlo, asi que se guarda y se aplica en `enterApp`. Ahi el canal pedido pasa
'                a ser el canal INICIAL, en vez de sintonizar el primero y saltar al pedido: eso
'                serian dos streams para una sola pulsacion, y Roku mide el tiempo hasta el primer
'                fotograma (criterio 3.6, 8 s).
'
'   app abierta  hay catalogo, asi que se resuelve en el momento y se manda a la pantalla por el
'                camino normal, el mismo que usan Buscar y Mi lista — con sus controles de acceso.

sub onDeepLink()
    enlace = m.global.deepLink

    if not deepLinkIsValid(enlace)
        ' Un enlace roto con la app abierta SI se avisa: el usuario acaba de pedir algo y merece
        ' saber que no se pudo. En frio no, que seria un aviso sobre la bienvenida sin que el
        ' usuario haya pedido nada — el arranque normal entra por aqui con reason = "none".
        if enlace <> invalid and enlace.reason <> "none" and m.global.isLoggedIn
            showToast(tvDeepLinkNotFoundText())
        end if
        return
    end if

    ' Todavia sin sesion: se guarda para cuando la haya. Si el usuario tiene que escribir el login,
    ' el enlace sigue esperando y entra en cuanto termine.
    if not m.global.isLoggedIn
        rememberDeepLink(enlace)
        return
    end if

    if m.mainScreen = invalid then return

    if tvFindChannelByCnId(m.global.channels, enlace.cnId) = invalid
        print "[TV] enlace profundo: el canal "; enlace.cnId; " no esta en el catalogo"
        showToast(tvDeepLinkNotFoundText())
        return
    end if

    print "[TV] enlace profundo con la app abierta: canal "; enlace.cnId
    m.mainScreen.deepLinkCnId = enlace.cnId
end sub

sub rememberDeepLink(enlace as object)
    if not deepLinkIsValid(enlace) then return
    print "[TV] enlace profundo pendiente: canal "; enlace.cnId
    m.pendingDeepLink = enlace
end sub

' `deepLink` es un campo del nodo global, asi que puede llegar como array vacio antes de que
' main.brs lo rellene. No basta con comprobar invalid.
function deepLinkIsValid(enlace as object) as boolean
    if enlace = invalid then return false
    if enlace.valid = invalid then return false
    return enlace.valid
end function

' ---- CU-01: arranque ---------------------------------------------------------
'
' La navegacion la decide LA SESION, no el flujo: si hay una guardada se entra directo a ver
' television, sin bienvenida y sin login. Escribir con el mando es incomodo, y esa diferencia es la
' que separa una app que se usa a diario de una que se abandona.
sub bootstrap()
    handle = tvSessionHandle()

    if not tvCanResumeSession(handle.email, handle.token, handle.password)
        showIntro()
        return
    end if

    print "[TV] sesion guardada: entrando sin login"
    m.resumeHandle = handle
    showResuming()

    ' Se revalida con el token. Si el backend dice que ya no vale, se cae al login — que es
    ' exactamente el caso previsto en CU-01 ("hay sesion pero el token ya no vale").
    url = tvApiGetWeb2Url(m.brand.baseUrl, handle.email, handle.password, tvSessionDeviceId(), m.brand.platform, handle.token)

    m.resumeTask = CreateObject("roSGNode", "ApiTask")
    m.resumeTask.observeField("response", "onResumeResponse")
    m.resumeTask.request = tvApiRequest(url)
    m.resumeTask.control = "RUN"
end sub

' Pantalla de espera mientras se revalida. Certificacion 3.4 de Roku: hay que mostrar indicador si
' algo tarda mas de 3 s, y aqui se depende de una llamada de red.
sub showResuming()
    m.resumingLabel = m.top.findNode("resuming")
    m.resumingLabel.color = m.brand.textSecondary
    m.resumingLabel.visible = true
end sub

sub onResumeResponse()
    m.resumingLabel.visible = false
    response = m.resumeTask.response

    ' Sin red no se echa al usuario al login: no poder preguntar no es lo mismo que el servidor
    ' diciendo que no vales. Pero sin catalogo tampoco se puede mostrar television, asi que se
    ' entra al login, que es la unica pantalla util sin datos.
    if not response.ok or response.json = invalid or ResponseHasError(response.json)
        print "[TV] sesion guardada: no sirve, al login"
        tvSessionClear()
        showLogin()
        return
    end if

    enterApp({ userInfo: UserInfoFromJson(response.json), raw: response.json })
end sub

' Flujo igual que el rediseno Kotlin: Intro -> Login -> Main (docs/DISENO.md 2.1).
sub showIntro()
    intro = CreateObject("roSGNode", "IntroScreen")
    intro.observeField("done", "onIntroDone")
    replaceStack(intro)
end sub

sub onIntroDone()
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
    enterApp(session)
end sub

' El UNICO camino de entrada a la app. Lo usan el login y el arranque con sesion guardada, para que
' no haya dos sitios que monten el estado y se vayan separando.
sub enterApp(session as object)
    ' El estado de sesión vive en el nodo global: cualquier pantalla lo observa desde ahí, nadie se
    ' lo pasa a nadie (docs/arquitectura_flujo.md §3).
    m.global.session = session.userInfo

    ' CU-03: el asidero de la sesion se guarda SIEMPRE, marque el usuario "recordarme" o no. Son
    ' dos cosas distintas: esto es poder seguir hablando con el servidor en nombre del usuario;
    ' "recordarme" es rellenarle el formulario cuando CIERRE sesion.
    tvSessionSaveHandle(session.userInfo.userEmail, session.userInfo.token)
    m.global.isLoggedIn = true

    catalog = tvFlattenCatalog(session.raw)
    m.global.channels = catalog.channels
    m.global.sections = catalog.sections

    print "[TV] catalogo: "; catalog.channels.Count(); " canales reproducibles en "; catalog.sections.Count(); " categorias"

    ' Certificacion 5.1 — el enlace profundo del arranque en frio se resuelve AQUI, que es el
    ' primer instante en que hay un catalogo contra el que comprobarlo. Si el canal ya no existe
    ' (lo quitaron del plan, o el enlace es de otro ISP) se arranca normal y se avisa: el enlace
    ' guardado en un Roku sobrevive al canal al que apunta.
    canalInicial = 0
    enlaceRoto = false
    if m.pendingDeepLink <> invalid
        if tvFindChannelByCnId(catalog.channels, m.pendingDeepLink.cnId) <> invalid
            canalInicial = m.pendingDeepLink.cnId
            print "[TV] enlace profundo: se arranca en el canal "; canalInicial
        else
            print "[TV] enlace profundo: el canal "; m.pendingDeepLink.cnId; " no esta en el catalogo"
            enlaceRoto = true
        end if
        m.pendingDeepLink = invalid
    end if

    main = CreateObject("roSGNode", "MainScreen")
    main.videoNode = m.videoPlayer

    ' ANTES de apilar: la pantalla reparte su arranque en pasos de 0,2 s y el canal inicial se
    ' elige en el primero. Puesto aqui llega de sobra, y asi NO se sintoniza un canal para
    ' cambiarlo acto seguido.
    if canalInicial > 0 then main.startCnId = canalInicial
    main.observeField("logout", "onLogout")
    main.observeField("blockedReason", "onBlockedChannel")
    main.observeField("catchupTarget", "onRequestCatchup")
    m.mainScreen = main
    replaceStack(main)

    m.catalogSignature = tvCatalogSignature(catalog.channels)
    m.heartbeatTimer.control = "start"
    m.revalidateTimer.control = "start"

    ' Al final: el aviso se ve sobre la pantalla ya montada, no sobre el login que acaba de irse.
    if enlaceRoto then showToast(tvDeepLinkNotFoundText())
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
    m.global.adultUnlocked = false
    m.global.channels = []
    m.global.sections = []
    showLogin()
end sub

' ---- CU-15: reproductor de grabaciones ---------------------------------------
'
' Es la UNICA pantalla apilada sobre "TV en directo" que reproduce. El directo ya no tiene una
' pantalla completa propia: es el mismo sitio con el overlay oculto (CU-12).

sub onRequestCatchup()
    destino = m.mainScreen.catchupTarget
    if destino = invalid then return

    player = CreateObject("roSGNode", "CatchupPlayer")
    player.videoNode = m.videoPlayer
    m.catchupPlayer = player

    ' "TV en directo" deja de reaccionar al estado del reproductor mientras dure la grabacion: el
    ' nodo Video es UNICO, y si no, los dos reintentos pelearian por el.
    m.global.catchupActive = true

    pushScreen(player, true)

    ' La grabacion se pone DESPUES de apilar: al asignarla arranca el video, y para eso la pantalla
    ' ya tiene que estar en el arbol con su nodo Video puesto.
    player.catchup = destino
end sub

' Al cerrar la grabacion hay que hacer DOS cosas, y ninguna es opcional (CU-10 y CU-15):
'   - volver a PREPARAR el directo: se detuvo para liberar el decodificador, y un "reanudar" no
'     hace nada sobre un reproductor detenido — el canal se quedaria negro
'   - anclar la parrilla en la fila del canal DE LA GRABACION y devolver el foco a la grilla
sub syncAfterCatchup()
    if m.catchupPlayer = invalid then return
    if m.mainScreen = invalid then return

    ancla = m.catchupPlayer.anchorCnId
    m.catchupPlayer = invalid
    m.global.catchupActive = false

    m.mainScreen.resumeLive = true
    if ancla > 0 then m.mainScreen.catchupAnchorCnId = ancla
end sub

' ---- modales -----------------------------------------------------------------
'
' Los cuatro casos del original comparten componente (docs/DISENO.md 2.7). La escena es la duena:
' asi el ATRAS tiene una sola prioridad y ningun panel de debajo se queda el foco.

sub showModal(kind as string, titulo as string, mensaje as string, botonTexto = "" as string)
    m.modalKind = kind
    m.appModal.titulo = titulo
    m.appModal.mensaje = mensaje
    m.appModal.botonTexto = botonTexto
    m.appModal.visible = true
    m.appModal.setFocus(true)
end sub

sub hideModal()
    m.modalKind = ""
    m.appModal.visible = false
    if m.stack.Count() > 0 then m.stack[m.stack.Count() - 1].setFocus(true)
end sub

sub onModalAction()
    if m.modalKind = "offline" and m.appModal.action = "accept"
        ' Reintentar: si ya hay red, el sondeo de 5 s lo detecta y cierra el modal solo.
        onNetworkCheck()
        return
    end if

    hideModal()
end sub

' Lo piden las pantallas cuando un canal no se puede reproducir.
sub onBlockedChannel()
    razon = m.mainScreen.blockedReason
    if razon = "" then return

    if razon = "adult"
        ' El PIN es LOCAL del aparato: el backend manda un hash bcrypt que Roku no puede verificar
        ' (domain/usecase/ParentalPin.brs). Si aun no hay PIN, el primer paso es crearlo.
        m.pinModal.paso = tvParentalStep(tvHasParentalPin(), m.global.adultUnlocked)
        m.pinModal.visible = true
        m.pinModal.setFocus(true)
        return
    end if

    if razon = "premium"
        showModal("premium", "Contenido no incluido", "Este canal pertenece a un pack que no esta en tu plan. Para contratarlo, contacta con tu proveedor.")
        return
    end if

    if razon = "ip"
        showModal("ip", "Canal restringido", "Este canal no esta disponible desde tu conexion actual.")
        return
    end if

    if razon = "unplayable"
        showModal("unplayable", "Canal no disponible", "Este canal no esta disponible en tu plan.")
    end if
end sub

sub onPinAction()
    m.pinModal.visible = false

    if m.pinModal.action = "ok"
        ' Desbloqueado para TODA la sesion: pedir el PIN en cada canal adulto es insufrible con un
        ' mando (afinado asi en el port a Kotlin). Se reinicia al cerrar sesion.
        m.global.adultUnlocked = true
        if m.mainScreen <> invalid then m.mainScreen.adultUnlocked = true
        return
    end if

    if m.stack.Count() > 0 then m.stack[m.stack.Count() - 1].setFocus(true)
end sub

' ---- CU-25: aviso flotante ---------------------------------------------------

sub showToast(texto as string)
    m.toast.text = texto
    m.top.findNode("toastLayer").visible = true
    m.toastTimer.control = "stop"
    m.toastTimer.control = "start"
end sub

sub onToastTimer()
    m.top.findNode("toastLayer").visible = false

    ' La ventana del doble ATRAS vence a la vez que el aviso: si el usuario no insistio, el
    ' contador vuelve a empezar y el siguiente ATRAS vuelve a avisar en vez de cerrar.
    m.lastBackMs = 0&
end sub

' ---- CU-18: conectividad ------------------------------------------------------
'
' SceneGraph no avisa por push de los cambios de red, asi que se sondea. El modal tiene guard
' propio: si ya esta abierto no se vuelve a abrir, para no robar el foco en cada comprobacion.

sub onNetworkCheck()
    info = CreateObject("roDeviceInfo")
    hayRed = info.GetLinkStatus()

    m.global.isOnline = hayRed

    if tvShouldShowOfflineModal(hayRed, m.modalKind = "offline")
        showModal("offline", "Sin conexion", "Para acceder al contenido debes estar conectado a internet.", "Reconectar")
        return
    end if

    ' Al volver la red, el modal se cierra solo.
    if hayRed and m.modalKind = "offline" then hideModal()
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
    applyRefreshRhythm()

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

' CU-04 — El ritmo se adapta: 60 s en el caso sano, 8 s mientras la pantalla esta DEGRADADA (sin
' canal reproducible o sin guia). Reintentar seguido engancha la recuperacion en cuanto el servidor
' vuelve; el caso sano, que es casi todo el tiempo, no paga ese coste.
sub applyRefreshRhythm()
    canales = m.global.channels
    hayCanal = (canales <> invalid and canales.Count() > 0)
    hayGuia = not m.global.guideDegraded

    intervalo = tvRefreshIntervalSec(hayCanal, hayGuia)
    if m.revalidateTimer.duration = intervalo then return

    print "[TV] revalidacion: ritmo a "; intervalo; " s"
    m.revalidateTimer.duration = intervalo
    m.revalidateTimer.control = "stop"
    m.revalidateTimer.control = "start"
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
        ' El modal es lo primero de la prioridad.
        if m.pinModal.visible
            m.pinModal.visible = false
            if m.stack.Count() > 0 then m.stack[m.stack.Count() - 1].setFocus(true)
            return true
        end if

        if m.appModal.visible
            hideModal()
            return true
        end if

        ' Prioridad (docs/plan_migracion.md §6): modal → pantalla completa → EPG → pantalla apilada
        ' → pestaña inicial → cerrar el canal. Los primeros niveles los resuelve cada pantalla y solo
        ' llega aquí lo que nadie ha consumido.
        if m.stack.Count() > 1
            popScreen()
            syncAfterCatchup()
            return true
        end if

        ' ---- CU-25: en la raiz, salir con DOBLE ATRAS ----
        '
        ' La confirmacion es por doble pulsacion y no por un dialogo con botones: un dialogo obliga
        ' a mover el foco hasta "Si" y aceptar, o sea tres pulsaciones para algo que deberia ser
        ' inmediato. Cerrar sin querer es de las cosas mas molestas que hace una app de TV.
        '
        ' Devolver `false` aqui es lo que cierra el canal: Roku lo interpreta como "nadie ha
        ' consumido el ATRAS en la raiz".
        ahora& = tvNowMs()
        if tvShouldExitOnBack(ahora&, m.lastBackMs)
            m.videoPlayer.control = "stop"
            return false
        end if

        m.lastBackMs = ahora&
        showToast(tvExitHintText())
        return true
    end if

    return false
end function
