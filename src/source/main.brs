' Entrada del canal. Ver docs/arquitectura_flujo.md §1 y §2.
'
' Regla: una sola Scene para todo el canal. Cambiar de escena en Roku destruye el árbol de nodos y
' con él el nodo Video — eso rompería el zapping y obligaría a recrear el decodificador en cada
' navegación, justo lo que docs/BACKEND-GOTCHAS.md §9 dice que hay que evitar.

' `args` trae el ENLACE PROFUNDO cuando la app no se abre desde su icono, sino desde el buscador
' del Roku o desde un atajo del sistema (certificación 5.1/5.2, domain/usecase/DeepLink.brs).
' En un arranque normal llega con los argumentos propios de Roku y ningún `contentId`.
sub Main(args as dynamic)
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)

    ' Nodo global: el estado compartido y observable de toda la sesión.
    ' Reemplaza las ~25 variables globales del original (ver docs/arquitectura_flujo.md §3).
    '
    ' OJO: `global` es palabra RESERVADA en BrightScript y no se puede usar como nombre de variable.
    ' El error que da es "Unable to cast Object to Interface", que no lo sugiere para nada.
    globalNode = screen.GetGlobalNode()
    globalNode.AddFields({
        brand: BrandConfig()

        ' --- Sesión (CU-01, 04, 17) ---
        ' OJO: el valor inicial define el TIPO del campo. Con `invalid` el campo queda sin tipo
        ' y las asignaciones posteriores se DESCARTAN EN SILENCIO (docs/ROKU-GOTCHAS.md §19).
        ' Por eso la sesión y la guía arrancan como arrays asociativos vacíos, no como invalid.
        session: {}               ' UserInfo en memoria; lo persistente va al registry
        isLoggedIn: false

        ' --- Catálogo (CU-05, 06, 07, 11, 12) ---
        channels: []
        sections: []
        favoriteIds: []

        ' Canal en emisión, para el heartbeat del dashboard (CU-16)
        currentCnId: 0

        ' CU-14: adultos desbloqueados en esta sesion (se reinicia al cerrar sesion)
        adultUnlocked: false

        ' --- Guía (CU-14) ---
        epg: {}

        ' CU-04: la pantalla está DEGRADADA si la guía no llegó. Mientras lo esté, la revalidación
        ' baja de 60 s a 8 s para engancharla en cuanto el servidor se recupere.
        guideDegraded: false

        ' --- Conectividad (CU-18) ---
        isOnline: true

        ' CU-15: hay una grabacion abierta encima. El nodo Video es UNICO y compartido, asi que
        ' "TV en directo" tiene que dejar de reaccionar a su estado mientras no sea suyo: si no,
        ' su reintento competiria con el de la grabacion por el mismo reproductor.
        catchupActive: false
    })

    ' El enlace profundo va aparte porque necesita `alwaysNotify` y `AddFields` (en plural) no lo
    ' admite. Sin él, pedir DOS VECES SEGUIDAS el mismo canal no avisaría la segunda vez: el valor
    ' no cambió. Y eso es exactamente lo que hace el revisor de Roku al probar los enlaces.
    globalNode.AddField("deepLink", "assocarray", true)

    ' ARRANQUE EN FRÍO. Se deja puesto ANTES de crear la escena, no después: así MainScene lo
    ' encuentra ya ahí en su `init()` y puede entrar directamente al canal pedido. Si se asignara
    ' después, habría una carrera con el arranque de la sesión.
    globalNode.deepLink = tvParseDeepLink(args)

    screen.CreateScene("MainScene")
    screen.Show()

    ' CANAL YA ABIERTO. Cuando la app está en marcha, Roku NO vuelve a llamar a Main: manda el
    ' enlace como un `roInputEvent` a este objeto. Sin crearlo, un enlace recibido con la app
    ' abierta se pierde sin dejar rastro — y es el caso que más se prueba en certificación,
    ' porque es lo que pasa al volver al buscador del Roku sin cerrar la app.
    '
    ' Tiene que seguir VIVO todo el bucle: si se recogiera la basura, los eventos dejarían de
    ' llegar y el fallo sería intermitente. Por eso es una variable del propio Main.
    entrada = CreateObject("roInput")
    entrada.SetMessagePort(port)

    while true
        msg = wait(0, port)
        tipo = type(msg)

        if tipo = "roSGScreenEvent"
            ' Atrás en la pantalla raíz cierra el canal: en Roku no hay "salir de la app" propio
            ' y no conviene inventar un diálogo de confirmación (docs/ROKU-GOTCHAS.md §7).
            if msg.isScreenClosed() then return
        else if tipo = "roInputEvent"
            if msg.IsInput() then globalNode.deepLink = tvParseDeepLink(msg.GetInfo())
        end if
    end while
end sub
