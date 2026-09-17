' Accesores TOLERANTES al JSON del backend.
'
' Razón de existir: docs/BACKEND-GOTCHAS.md §6 — los campos del backend aparecen y desaparecen en
' caliente (se vio en vivo: `catchup` apareció a media tarde, `plan`/`planes` al día siguiente, y
' hubo un rato con 57 canales sin `url`). Que falte un campo NO puede romper el parseo.
'
' Y §11: `user_id` llega como NÚMERO en unos ISP y como TEXTO en otros. Por eso `jsonStr` acepta
' números y `jsonInt` acepta textos: se pide el tipo que se necesita, no el que mandó el backend.

function jsonStr(obj as object, key as string, fallback = "" as string) as string
    v = jsonRaw(obj, key)
    if v = invalid then return fallback
    if tvIsString(v) then return v
    if tvIsNumber(v) then return Str(v).Trim()
    return fallback
end function

function jsonInt(obj as object, key as string, fallback = 0 as integer) as integer
    v = jsonRaw(obj, key)
    if v = invalid then return fallback
    if tvIsNumber(v) then return Int(v)
    if tvIsString(v)
        if v.Trim() = "" then return fallback
        return Int(Val(v))
    end if
    if tvIsBool(v)
        if v then return 1
        return 0
    end if
    return fallback
end function

' Acepta true/false, 1/0 y "true"/"1" — los tres los manda el backend según el campo.
function jsonBool(obj as object, key as string, fallback = false as boolean) as boolean
    v = jsonRaw(obj, key)
    if v = invalid then return fallback
    if tvIsBool(v) then return v
    if tvIsNumber(v) then return Int(v) <> 0
    if tvIsString(v)
        low = LCase(v.Trim())
        return low = "true" or low = "1"
    end if
    return fallback
end function

' Siempre devuelve un array recorrible: nunca invalid, así el llamador no necesita guard.
function jsonArray(obj as object, key as string) as object
    v = jsonRaw(obj, key)
    if v = invalid then return []
    if type(v) = "roArray" then return v
    return []
end function

function jsonObj(obj as object, key as string) as object
    v = jsonRaw(obj, key)
    if v = invalid then return invalid
    if type(v) = "roAssociativeArray" then return v
    return invalid
end function

' ---- internos ----------------------------------------------------------------

function jsonRaw(obj as object, key as string) as object
    if obj = invalid then return invalid
    if type(obj) <> "roAssociativeArray" then return invalid
    if not obj.DoesExist(key) then return invalid
    return obj[key]
end function

function tvIsString(v as object) as boolean
    t = type(v)
    return t = "String" or t = "roString"
end function

function tvIsNumber(v as object) as boolean
    t = type(v)
    return t = "Integer" or t = "roInt" or t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble" or t = "LongInteger" or t = "roLongInteger"
end function

function tvIsBool(v as object) as boolean
    t = type(v)
    return t = "Boolean" or t = "roBoolean"
end function
