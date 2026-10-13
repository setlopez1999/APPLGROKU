' Enlaces profundos: abrir la app YA DENTRO de un canal.
'
' Es un REQUISITO DE CERTIFICACION, no una mejora. Roku no publica una app de video que no lo
' implemente: es como el buscador del Roku y la fila de "Continuar viendo" llevan al contenido.
'
'   canal cerrado   Main(args) recibe { contentId, mediaType }
'   canal abierto   llega un roInputEvent con los mismos dos campos
'                   (y el manifest necesita `supports_input_launch=1`, o Roku REINICIA la app
'                    entera en vez de mandar el evento)
'
' Se prueba asi:
'   curl -d '' "http://192.168.0.203:8060/launch/dev?contentId=2041&mediaType=livefeed"
'   curl -d '' "http://192.168.0.203:8060/input?contentId=2041&mediaType=livefeed"   (ya abierta)
'
' Que el `contentId` sea el `cn_id` y no el NUMERO del canal es deliberado: el numero se repite
' entre ISPs y el operador lo reordena cuando quiere, asi que un enlace guardado apuntaria a otro
' canal unos meses despues. El cn_id es estable.
'
' Esta pieza es logica pura a proposito: lo unico que de verdad hay que verificar de un enlace
' profundo es que NINGUNA entrada rara deje la app en blanco, y eso se prueba mejor con 30 casos
' en Node que abriendo el canal 30 veces a mano.

' Los que tienen sentido en una app que SOLO emite television en directo. Roku define ademas
' `movie`, `episode`, `season`, `series`, `shortFormVideo`, `tvSpecial` y `sportsevent`, que son de
' catalogos a la carta: aqui no hay nada a lo que puedan apuntar.
function tvDeepLinkSupportedTypes() as object
    return ["livefeed", "live", "channel"]
end function

' El tipo vacio SE ACEPTA. Roku exige mandar los dos campos, pero un enlace viejo o un integrador
' descuidado puede traer solo el `contentId`, y en ese caso rechazarlo seria negarse a abrir un
' canal que existe y que el usuario ha pedido. Lo que no se acepta es un tipo que diga claramente
' otra cosa ("movie"): ahi el enlace no es para esta app.
function tvIsSupportedMediaType(mediaType as string) as boolean
    if mediaType = "" then return true

    for each permitido in tvDeepLinkSupportedTypes()
        if LCase(mediaType) = permitido then return true
    end for
    return false
end function

' Lee un campo del array de argumentos SIN depender de las mayusculas.
'
' Roku documenta `contentId` y `mediaType`, pero lo que llega es literalmente lo que venga en la
' URL, y las herramientas de prueba de la propia Roku mandan `contentID` y `contentid`. Un enlace
' que no abre por una mayuscula es un fallo de certificacion que cuesta dias encontrar.
function tvDeepLinkField(args as object, nombre as string) as string
    if args = invalid then return ""

    buscado = LCase(nombre)
    for each clave in args
        if LCase(clave) = buscado
            valor = args[clave]
            if valor = invalid then return ""

            tipo = type(valor)
            if tipo = "String" or tipo = "roString" then return valor.Trim()
            if tipo = "Integer" or tipo = "roInt" or tipo = "roInteger" then return Str(valor).Trim()
            return ""
        end if
    end for
    return ""
end function

' Texto -> cn_id, o 0 si no vale.
'
' A mano y no con `Val()`: `Val("12abc")` devuelve 12 sin quejarse, y un enlace a medio escribir
' acabaria abriendo un canal que nadie pidio. Aqui o son todo digitos o no es un id.
'
' El tope de 9 digitos no es decorativo: `contentId` admite 255 caracteres y un entero de 32 bits
' desborda en silencio, dando un numero negativo que ademas podria coincidir con algo.
function tvDeepLinkIdFromString(valor as string) as integer
    if valor = "" then return 0
    if Len(valor) > 9 then return 0

    for i = 1 to Len(valor)
        caracter = Mid(valor, i, 1)
        if caracter < "0" or caracter > "9" then return 0
    end for

    return Int(Val(valor))
end function

' Lo que no se abre nunca: un enlace sin id, con un id que no es un numero o de un tipo que no
' emitimos. En los tres casos la app arranca NORMAL — nunca en una pantalla rota ni cerrandose,
' que es justo lo que comprueba el revisor de Roku cuando prueba un enlace invalido a proposito.
'
' Devuelve { valid, cnId, mediaType, reason } con reason en:
'   "ok"       hay un canal que abrir
'   "none"     arranque normal: no venia ningun enlace
'   "badId"    venia un enlace pero el id no sirve
'   "badType"  el tipo es de contenido que esta app no tiene
function tvParseDeepLink(args as object) as object
    vacio = { valid: false, cnId: 0, mediaType: "", reason: "none" }
    if args = invalid then return vacio

    contentId = tvDeepLinkField(args, "contentId")
    mediaType = tvDeepLinkField(args, "mediaType")

    ' Sin `contentId` no hay enlace profundo: es el arranque de siempre, desde el menu del Roku.
    if contentId = "" then return vacio

    if not tvIsSupportedMediaType(mediaType)
        return { valid: false, cnId: 0, mediaType: LCase(mediaType), reason: "badType" }
    end if

    cnId = tvDeepLinkIdFromString(contentId)
    if cnId <= 0
        return { valid: false, cnId: 0, mediaType: LCase(mediaType), reason: "badId" }
    end if

    return { valid: true, cnId: cnId, mediaType: LCase(mediaType), reason: "ok" }
end function

' El aviso cuando el enlace trae un canal que esta app no tiene: existio y lo quitaron, o es de
' otro ISP. No es un error de la app y no merece un modal que haya que cerrar.
function tvDeepLinkNotFoundText() as string
    return "Ese canal ya no está disponible"
end function
