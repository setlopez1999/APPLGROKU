' Entrada del canal. Ver docs/arquitectura_flujo.md §1 y §2.
'
' Regla: una sola Scene para todo el canal. Cambiar de escena en Roku destruye el árbol de nodos y
' con él el nodo Video — eso rompería el zapping y obligaría a recrear el decodificador en cada
' navegación, justo lo que docs/BACKEND-GOTCHAS.md §9 dice que hay que evitar.

sub Main()
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)

    ' Nodo global: el estado compartido y observable de toda la sesión.
    ' Reemplaza las ~25 variables globales del original (ver docs/arquitectura_flujo.md §3).
    global = screen.GetGlobalNode()
    global.AddFields({
        brand: BrandConfig()

        ' --- Sesión (CU-01, 04, 17) ---
        session: invalid          ' UserInfo en memoria; lo persistente va al registry
        isLoggedIn: false

        ' --- Catálogo (CU-05, 06, 07, 11, 12) ---
        channels: []
        sections: []
        favoriteIds: []

        ' --- Guía (CU-10) ---
        epg: invalid

        ' --- Conectividad (CU-18) ---
        isOnline: true
    })

    scene = screen.CreateScene("MainScene")
    screen.Show()

    while true
        msg = wait(0, port)
        if type(msg) = "roSGScreenEvent"
            ' Atrás en la pantalla raíz cierra el canal: en Roku no hay "salir de la app" propio
            ' y no conviene inventar un diálogo de confirmación (docs/ROKU-GOTCHAS.md §7).
            if msg.isScreenClosed() then return
        end if
    end while
end sub
