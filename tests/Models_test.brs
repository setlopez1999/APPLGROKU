sub testModels()
    tvSuite("domain/model — UserInfo, Plan, Channel")

    user = UserInfoFromJson(fxGetWeb2())
    tvAssertEqual(user.userEmail, "demo@isp.tv", "UserInfo lee el email")
    tvAssertEqual(user.userId, "4321", "user_id numérico se guarda como texto")
    tvAssertEqual(user.premiumsAllowed.Count(), 1, "premiumsallowed se parsea")
    tvAssertEqual(user.planes.Count(), 2, "planes se parsean")

    ' El mismo ISP otro día: user_id como texto (§11)
    degradado = UserInfoFromJson(fxGetWeb2Degradado())
    tvAssertEqual(degradado.userId, "4321", "user_id como texto da el mismo resultado")
    tvAssertEqual(degradado.planes.Count(), 0, "sin `planes` no revienta, devuelve lista vacía")
    tvAssertEqual(degradado.premiumsAllowed.Count(), 0, "sin `premiumsallowed` devuelve lista vacía")
    tvAssertEqual(degradado.plan, "", "sin `plan` devuelve cadena vacía")

    ' "Básico - $10" → nombre y precio separados (options.js:145-150)
    plan = PlanFromJson({ nombre: "Básico - $10", cantidad_canales: 23 })
    tvAssertEqual(plan.nombre, "Básico", "el nombre del plan se separa del precio")
    tvAssertEqual(plan.precio, "$10", "el precio del plan se extrae")
    tvAssertEqual(plan.cantidadCanales, 23, "cantidad de canales del plan")

    sinPrecio = PlanFromJson({ nombre: "Plan Único", cantidad_canales: 5 })
    tvAssertEqual(sinPrecio.nombre, "Plan Único", "plan sin "" - "" conserva el nombre entero")
    tvAssertEqual(sinPrecio.precio, "", "plan sin "" - "" deja el precio vacío")

    ' El error del backend viaja con HTTP 200
    tvAssertEqual(ResponseHasError({ error: true, message: "usuario no existe" }), true, "detecta error:true")
    tvAssertEqual(ResponseErrorMessage({ error: true, message: "usuario no existe" }), "usuario no existe", "lee el mensaje de error")
    tvAssertEqual(ResponseErrorMessage({ error: true }), "credenciales incorrectas", "mensaje por defecto si no viene")
    tvAssertEqual(ResponseHasError(fxGetWeb2()), false, "respuesta buena no es error")
end sub
