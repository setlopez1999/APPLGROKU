sub testParentalPin()
    tvSuite("domain/usecase/ParentalPin — CU-14 con PIN local")

    tvAssertEqual(tvIsValidPinFormat("1234"), true, "cuatro dígitos es válido")
    tvAssertEqual(tvIsValidPinFormat("0000"), true, "ceros también")
    tvAssertEqual(tvIsValidPinFormat("123"), false, "tres dígitos no")
    tvAssertEqual(tvIsValidPinFormat("12345"), false, "cinco tampoco")
    tvAssertEqual(tvIsValidPinFormat("12a4"), false, "con una letra no")
    tvAssertEqual(tvIsValidPinFormat("12 4"), false, "con un espacio tampoco")
    tvAssertEqual(tvIsValidPinFormat(""), false, "vacío no")
    tvAssertEqual(tvIsValidPinFormat(invalid), false, "invalid no revienta")
    tvAssertEqual(tvIsValidPinFormat(1234), false, "un número no vale: se maneja como texto")

    tvSuite("ParentalPin — qué hacer al abrir un canal de adultos")

    tvAssertEqual(tvParentalStep(false, false), "create", "sin PIN guardado, hay que crearlo")
    tvAssertEqual(tvParentalStep(true, false), "ask", "con PIN guardado, se pide")

    ' Pedir el PIN en CADA canal adulto es insufrible con un mando: se desbloquea por sesión
    tvAssertEqual(tvParentalStep(true, true), "allow", "ya validado en esta sesión: pasa sin preguntar")
    tvAssertEqual(tvParentalStep(false, true), "allow", "el desbloqueo de sesión manda")

    tvSuite("ParentalPin — intentos")

    crear = tvCheckPinAttempt("create", "1234", false)
    tvAssertEqual(crear.ok, true, "al crear, cualquier PIN bien formado vale")
    tvAssertEqual(crear.guardar, true, "y hay que guardarlo")

    malFormado = tvCheckPinAttempt("create", "12", false)
    tvAssertEqual(malFormado.ok, false, "un PIN mal formado se rechaza al crear")
    tvAssertEqual(malFormado.error, "El PIN debe tener 4 dígitos", "con su mensaje")

    correcto = tvCheckPinAttempt("ask", "1234", true)
    tvAssertEqual(correcto.ok, true, "el PIN correcto abre")
    tvAssertEqual(correcto.guardar, false, "y no se vuelve a guardar")

    incorrecto = tvCheckPinAttempt("ask", "9999", false)
    tvAssertEqual(incorrecto.ok, false, "el PIN incorrecto no abre")
    tvAssertEqual(incorrecto.error, "PIN incorrecto", "con su mensaje")

    ' El formato se valida ANTES que la coincidencia: si no, un PIN de 2 dígitos daría
    ' "PIN incorrecto" en vez de decir qué pasa de verdad
    corto = tvCheckPinAttempt("ask", "99", false)
    tvAssertEqual(corto.error, "El PIN debe tener 4 dígitos", "el formato se comprueba primero")

    tvAssertEqual(tvParentalTitle("create"), "Crea tu PIN parental", "título al crear")
    tvAssertEqual(tvParentalTitle("ask"), "Introduce tu PIN parental", "título al pedir")

    ' El aviso de que este PIN es solo de este aparato tiene que estar: si no, el usuario cree que
    ' es el mismo del móvil y se vuelve loco
    tvAssert(Instr(1, tvParentalMessage("create"), "solo en este dispositivo") > 0, "al crear se avisa de que el PIN es local")
end sub
