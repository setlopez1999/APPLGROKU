' Respuestas de ejemplo con la FORMA real del backend (docs/BACKEND-GOTCHAS.md §12).
' Cuando haya cuenta de prueba, estas fixtures se sustituyen por capturas reales de get-web2.

' get-web2 con los casos que importan mezclados a propósito:
'  - Nacionales: sección normal, dentro del plan
'  - Deportes:   FUERA del plan → todos sus canales con url vacía → la sección debe desaparecer
'  - Premium:    sección premium (st_id 30)
'  - Adultos:    sección adulta (st_id 40) + un canal que trae `adulto` solo en el canal
function fxGetWeb2() as object
    return {
        user: "Demo"
        user_email: "demo@isp.tv"
        user_id: 4321
        token: "tok-abc"
        plan: "Básico - $10"
        planes: [
            { nombre: "Básico - $10", cantidad_canales: 23 }
            { nombre: "Full - $25", cantidad_canales: 50 }
        ]
        email_soporte: "soporte@isp.tv"
        fono_soporte: "+51999999999"
        parentlockcode: "$2a$10$abcdefghijklmnopqrstuv"
        premiumsallowed: [30]
        use_multicdn: false
        sections: [
            {
                st_id: 1
                nombre: "Entretenimiento"
                sections: [
                    {
                        st_id: 10
                        nombre: "Nacionales"
                        premium: 0
                        adulto: 0
                        canales: [
                            { cn_id: 101, nombre: "Nativa", numero: 1, url: "https://h:1936/transcoderip/nativa.stream/playlist.m3u8", short_link: "nativa", catchup: 1 }
                            { cn_id: 102, nombre: "Latina", numero: 2, url: "https://h:1936/failover-SRT/latina.stream/playlist.m3u8", short_link: "latina", catchup: 1 }
                        ]
                    }
                    {
                        st_id: 20
                        nombre: "Deportes"
                        premium: 0
                        adulto: 0
                        canales: [
                            { cn_id: 201, nombre: "Deporte 1", numero: 10, url: "", short_link: "" }
                            { cn_id: 202, nombre: "Deporte 2", numero: 11, url: "", short_link: "" }
                        ]
                    }
                ]
            }
            {
                st_id: 2
                nombre: "Packs"
                sections: [
                    {
                        st_id: 30
                        nombre: "Cine Premium"
                        premium: 1
                        adulto: 0
                        canales: [
                            { cn_id: 301, nombre: "Cine HD", numero: 30, url: "https://h:1936/transcoderip2/cine.stream/playlist.m3u8", short_link: "cine" }
                        ]
                    }
                    {
                        st_id: 40
                        nombre: "Adultos"
                        premium: 0
                        adulto: 1
                        canales: [
                            { cn_id: 401, nombre: "XXX 1", numero: 90, url: "https://h:1936/transcoderip/x1.stream/playlist.m3u8", short_link: "x1" }
                        ]
                    }
                    {
                        st_id: 50
                        nombre: "Mixta"
                        premium: 0
                        adulto: 0
                        canales: [
                            { cn_id: 501, nombre: "Normal", numero: 60, url: "https://h:1936/transcoderip/n.stream/playlist.m3u8", short_link: "n" }
                            ' Adulto declarado SOLO en el canal, no en la sección (visto en respuesta real)
                            { cn_id: 502, nombre: "Picante", numero: 61, adulto: 1, url: "https://h:1936/transcoderip/p.stream/playlist.m3u8", short_link: "p" }
                        ]
                    }
                ]
            }
        ]
    }
end function

' Respuesta de api/get-epgguide. Día base: 1699920000 (medianoche UTC).
' Los programas van DESORDENADOS a propósito: no todos los ISP los mandan por hora.
'   Mañanero  09:00-12:00      Mediodía  12:00-14:00      Nocturno  20:00-23:00
' Entre las 14:00 y las 20:00 hay un HUECO, que también es un caso real.
function fxEpgGuide() as object
    return [
        {
            cn_id: 101
            epg: [
                { titulo: "Mediodía", fecha_ini: 1699963200, fecha_fin: 1699970400 }
                { titulo: "Nocturno", fecha_ini: 1699992000, fecha_fin: 1700002800 }
                { titulo: "Mañanero", fecha_ini: 1699952400, fecha_fin: 1699963200 }
            ]
        }
        {
            cn_id: 102
            epg: [
                { titulo: "Noticias", fecha_ini: 1699952400, fecha_fin: 1699956000 }
            ]
        }
    ]
end function

' Respuesta del servicio de notificaciones. Llega de más VIEJA a más NUEVA; la app la invierte.
' La primera ya está leída: sirve para separar "no leída" de "nueva".
function fxNotifications() as object
    return {
        message: [
            { id: "1", title: "Aviso", text: "La más vieja", read: 1, created_at: "2026-09-15 08:00:00" }
            { id: "2", title: "Aviso", text: "Intermedia", read: 0, created_at: "2026-09-16 10:00:00" }
            { id: "3", title: "Aviso", text: "La más nueva", read: 0, created_at: "2026-09-17 09:00:00" }
        ]
    }
end function

' El mismo backend pero en uno de sus días malos (§6): sin `plan`, sin `planes`, sin `premiumsallowed`,
' sin `catchup`, y con `user_id` como TEXTO en vez de número (§11).
function fxGetWeb2Degradado() as object
    return {
        user: "Demo"
        user_email: "demo@isp.tv"
        user_id: "4321"
        token: "tok-abc"
        sections: [
            {
                st_id: 1
                nombre: "Entretenimiento"
                sections: [
                    {
                        st_id: 10
                        nombre: "Nacionales"
                        canales: [
                            { cn_id: 101, nombre: "Nativa", numero: 1, url: "https://h:1936/transcoderip/nativa.stream/playlist.m3u8" }
                        ]
                    }
                ]
            }
        ]
    }
end function
