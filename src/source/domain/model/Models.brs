' Modelos de dominio. Espejo de app-lg/docs/cu/MODELS.md, con parseo tolerante (util/Json.brs).
'
' Regla heredada del Kotlin: los modelos SOLO incluyen campos verificados contra MODELS.md o contra
' una respuesta real. No se inventan campos especulativos.

' ---- Channel -----------------------------------------------------------------
' `url` es la CRUDA del backend. La url efectiva la resuelve FlattenCatalog, porque con multi-CDN
' se arma como multiCdnUrl + shortLink (docs/BACKEND-GOTCHAS.md §5).
function ChannelFromJson(json as object) as object
    return {
        cnId: jsonInt(json, "cn_id")
        nombre: jsonStr(json, "nombre")
        numero: jsonInt(json, "numero")
        imagen: jsonStr(json, "imagen")
        url: jsonStr(json, "url")
        shortLink: jsonStr(json, "short_link")
        audio: jsonInt(json, "audio")
        premium: jsonInt(json, "premium")
        adulto: jsonInt(json, "adulto")
        catchup: jsonInt(json, "catchup")
        restriccion: jsonInt(json, "restriccion")
        epg: EpgListFromJson(jsonArray(json, "epg"))

        ' Rellenados por FlattenCatalog a partir de la sección padre:
        streamUrl: ""
        sectionId: 0
        sectionNombre: ""
        sectionPremium: 0
        sectionAdulto: 0
        esAdulto: false
    }
end function

' ---- Section / Category ------------------------------------------------------
' OJO: el id de la sección es `st_id`, no `section_id`. En el port a Kotlin se usó `section_id` y las
' secciones quedaron con id=0, con premium/adulto mal mapeados. Verificado contra respuesta real.
function SectionFromJson(json as object) as object
    return {
        stId: jsonInt(json, "st_id")
        nombre: jsonStr(json, "nombre")
        premium: jsonInt(json, "premium")
        adulto: jsonInt(json, "adulto")
        imagen: jsonStr(json, "imagen")
        canales: jsonArray(json, "canales")

        ' Rellenado por FlattenCatalog:
        categoryIndex: 0
    }
end function

' ---- EpgProgram --------------------------------------------------------------
' fecha_ini / fecha_fin son Unix en SEGUNDOS (no milisegundos).
function EpgProgramFromJson(json as object) as object
    return {
        titulo: jsonStr(json, "titulo")
        fechaIni: jsonInt(json, "fecha_ini")
        fechaFin: jsonInt(json, "fecha_fin")
    }
end function

function EpgListFromJson(arr as object) as object
    out = []
    if arr = invalid then return out
    for each item in arr
        out.Push(EpgProgramFromJson(item))
    end for
    return out
end function

' ---- Plan --------------------------------------------------------------------
' `nombre` viene como "Básico - $10": el nombre y el precio van pegados con " - ".
function PlanFromJson(json as object) as object
    nombre = jsonStr(json, "nombre")
    partes = tvSplitPlanName(nombre)
    return {
        nombre: partes.nombre
        precio: partes.precio
        cantidadCanales: jsonInt(json, "cantidad_canales")
    }
end function

function tvSplitPlanName(nombre as string) as object
    idx = Instr(1, nombre, " - ")
    if idx > 0
        return {
            nombre: Left(nombre, idx - 1).Trim()
            precio: Mid(nombre, idx + 3).Trim()
        }
    end if
    return { nombre: nombre, precio: "" }
end function

' ---- UserInfo ----------------------------------------------------------------
' `user_id` llega como número en unos ISP y como texto en otros → se guarda como texto (§11).
' `url_ip` viene unas veces como `url_ip` y otras como `urlip` (visto en player.js:1275).
function UserInfoFromJson(json as object) as object
    urlIp = jsonStr(json, "url_ip")
    if urlIp = "" then urlIp = jsonStr(json, "urlip")

    planes = []
    for each p in jsonArray(json, "planes")
        planes.Push(PlanFromJson(p))
    end for

    premiums = []
    for each id in jsonArray(json, "premiumsallowed")
        premiums.Push(Int(id))
    end for

    return {
        user: jsonStr(json, "user")
        userEmail: jsonStr(json, "user_email")
        userId: jsonStr(json, "user_id")
        token: jsonStr(json, "token")
        plan: jsonStr(json, "plan")
        planes: planes
        emailSoporte: jsonStr(json, "email_soporte")
        fonoSoporte: jsonStr(json, "fono_soporte")
        whatsapp: jsonStr(json, "whatsapp")
        parentLockCode: jsonStr(json, "parentlockcode")
        premiumsAllowed: premiums
        useMultiCdn: jsonBool(json, "use_multicdn")
        urlIp: urlIp
        enabledVod: jsonBool(json, "enabledvod")
    }
end function

' El backend señala el fallo con `error: true` + `message`, con HTTP 200.
function ResponseHasError(json as object) as boolean
    return jsonBool(json, "error")
end function

function ResponseErrorMessage(json as object) as string
    msg = jsonStr(json, "message")
    if msg = "" then return "credenciales incorrectas"
    return msg
end function

' ¿Hay sesión de verdad? Una sesión "vacía" es un array asociativo SIN campos, no `invalid`: el nodo
' global necesita un valor inicial con tipo para poder guardarla (docs/ROKU-GOTCHAS.md §19).
function tvHasSession(userInfo as object) as boolean
    if userInfo = invalid then return false
    if type(userInfo) <> "roAssociativeArray" then return false
    return userInfo.DoesExist("userEmail")
end function
