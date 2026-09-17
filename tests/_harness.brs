' Arnés mínimo de tests. Corre en Node con `brs`, SIN dispositivo Roku.
'
' Esto es posible porque `domain/` y `data/` son BrightScript puro, sin nodos SceneGraph — la regla
' de capas de AGENTS.md. Lo que toca el dispositivo (red, registro, vídeo) vive en components/tasks
' y se prueba en el Roku.

sub tvTestInit()
    m.tvPass = 0
    m.tvFail = 0
    m.tvFailures = []
end sub

sub tvSuite(name as string)
    print ""
    print "  " + name
end sub

sub tvAssert(condition as boolean, name as string)
    if condition
        m.tvPass = m.tvPass + 1
        print "    ok   " + name
    else
        m.tvFail = m.tvFail + 1
        m.tvFailures.Push(name)
        print "    FAIL " + name
    end if
end sub

sub tvAssertEqual(actual as object, expected as object, name as string)
    if tvValuesEqual(actual, expected)
        m.tvPass = m.tvPass + 1
        print "    ok   " + name
    else
        m.tvFail = m.tvFail + 1
        m.tvFailures.Push(name)
        print "    FAIL " + name + "  (esperado: " + tvToStr(expected) + "  real: " + tvToStr(actual) + ")"
    end if
end sub

sub tvAssertInvalid(actual as object, name as string)
    tvAssert(actual = invalid, name)
end sub

function tvValuesEqual(a as object, b as object) as boolean
    if a = invalid and b = invalid then return true
    if a = invalid or b = invalid then return false
    return tvToStr(a) = tvToStr(b)
end function

function tvToStr(v as object) as string
    if v = invalid then return "invalid"
    if tvIsString(v) then return """" + v + """"
    if tvIsBool(v)
        if v then return "true"
        return "false"
    end if
    if tvIsNumber(v) then return Str(v).Trim()
    if type(v) = "roArray" then return "array(" + Str(v.Count()).Trim() + ")"
    if type(v) = "roAssociativeArray" then return "aa"
    return type(v)
end function

function tvTestExitCode() as integer
    print ""
    print "  ----------------------------------------"
    if m.tvFail = 0
        print "  " + Str(m.tvPass).Trim() + " tests, 0 fallos"
        print ""
        return 0
    end if
    print "  " + Str(m.tvPass).Trim() + " ok, " + Str(m.tvFail).Trim() + " FALLOS:"
    for each f in m.tvFailures
        print "    - " + f
    end for
    print ""
    return 1
end function
