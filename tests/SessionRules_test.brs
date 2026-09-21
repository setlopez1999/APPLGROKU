sub testSessionRules()
    tvSuite("domain/usecase/SessionRules — deviceId (CU-01)")

    id = tvGenerateDeviceId()
    tvAssertEqual(Len(id), 10, "el deviceId tiene 10 dígitos")
    tvAssertEqual(Instr(1, id, "-") = 0, true, "y no contiene guiones")
    tvAssertEqual(Left(id, 1) <> "0", true, "no empieza por cero (si no, serían 9 dígitos útiles)")
    tvAssertEqual(tvIsValidDeviceId(id), true, "el generado se considera válido")

    ' Se regenera si falta o si es una MAC vieja
    tvAssertEqual(tvIsValidDeviceId(invalid), false, "sin deviceId guardado hay que generarlo")
    tvAssertEqual(tvIsValidDeviceId(""), false, "cadena vacía tampoco vale")
    tvAssertEqual(tvIsValidDeviceId("a1-b2-c3-d4-e5"), false, "una MAC guardada por versiones viejas se descarta")
    tvAssertEqual(tvIsValidDeviceId(1234567890), false, "un número no vale: se persiste como texto")
    tvAssertEqual(tvIsValidDeviceId("1234567890"), true, "un id guardado correcto se conserva")

    tvSuite("SessionRules — qué sobrevive al logout (CU-04)")

    sinRecordar = tvKeysToPreserveOnLogout(false)
    tvAssertEqual(sinRecordar.Count(), 2, "sin recordarme sobreviven dos claves")
    tvAssertEqual(sinRecordar[0], "deviceId", "el deviceId")

    ' Si el PIN parental se borrara al cerrar sesión, cualquiera lo saltaría haciendo logout
    tvAssertEqual(tvShouldKeepKeyOnLogout("parentalPin", false), true, "y el PIN parental, que si no se saltaría con un logout")

    conRecordar = tvKeysToPreserveOnLogout(true)
    tvAssertEqual(conRecordar.Count(), 5, "con recordarme sobreviven cinco")
    tvAssertEqual(tvShouldKeepKeyOnLogout("email", true), true, "el email se conserva si hay recordarme")
    tvAssertEqual(tvShouldKeepKeyOnLogout("email", false), false, "y se borra si no lo hay")

    ' El deviceId se conserva SIEMPRE: si se regenera, el backend ve un aparato nuevo cada vez
    tvAssertEqual(tvShouldKeepKeyOnLogout("deviceId", false), true, "el deviceId sobrevive incluso sin recordarme")

    ' El password de SESIÓN no es el de "recordarme": ese se borra siempre
    tvAssertEqual(tvShouldKeepKeyOnLogout("sessionPassword", true), false, "el password de sesión NO sobrevive al logout")
    tvAssertEqual(tvShouldKeepKeyOnLogout("userInfo", true), false, "ni los datos de sesión")
    tvAssertEqual(tvShouldKeepKeyOnLogout("token", true), false, "ni el token")

    tvSuite("SessionRules — validación del formulario de login")

    tvAssertEqual(tvValidateLoginForm("demo@isp.tv", "clave"), "", "credenciales con forma válida pasan")
    tvAssertEqual(tvValidateLoginForm("demo", "clave"), "Ingrese un email válido", "email sin arroba se rechaza")
    tvAssertEqual(tvValidateLoginForm("demo@isp", "clave"), "Ingrese un email válido", "email sin punto se rechaza")
    tvAssertEqual(tvValidateLoginForm("", "clave"), "Ingrese un email válido", "email vacío se rechaza")
    tvAssertEqual(tvValidateLoginForm("demo@isp.tv", ""), "Ingrese su contraseña", "password vacío se rechaza")
    tvAssertEqual(tvValidateLoginForm("demo@isp.tv", "   "), "Ingrese su contraseña", "password de solo espacios también")

    tvAssertEqual(tvLooksLikeEmail("a@b.co"), true, "email mínimo válido")
    tvAssertEqual(tvLooksLikeEmail("@isp.tv"), false, "sin nada antes de la arroba")
    tvAssertEqual(tvLooksLikeEmail("a@@isp.tv"), false, "dos arrobas")
    tvAssertEqual(tvLooksLikeEmail("a@isp."), false, "sin nada después del punto")
end sub
