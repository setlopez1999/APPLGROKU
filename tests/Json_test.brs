sub testJson()
    tvSuite("util/Json — parseo tolerante (BACKEND-GOTCHAS §6 y §11)")

    obj = { texto: "hola", numero: 42, numeroTexto: "42", flagBool: true, flagNum: 1, flagTexto: "true", lista: [1, 2], anidado: { a: 1 } }

    ' Lo normal
    tvAssertEqual(jsonStr(obj, "texto"), "hola", "jsonStr lee un texto")
    tvAssertEqual(jsonInt(obj, "numero"), 42, "jsonInt lee un número")

    ' Campo ausente: el caso del día que el backend dejó de mandar `catchup` y `planes`
    tvAssertEqual(jsonStr(obj, "noExiste"), "", "campo ausente devuelve el fallback")
    tvAssertEqual(jsonInt(obj, "noExiste", 7), 7, "fallback propio si se pide")
    tvAssertEqual(jsonArray(obj, "noExiste").Count(), 0, "array ausente devuelve [] recorrible")
    tvAssertInvalid(jsonObj(obj, "noExiste"), "objeto ausente devuelve invalid")

    ' Objeto nulo entero: get-web2 devolvió respuestas rotas más de una vez
    tvAssertEqual(jsonStr(invalid, "texto"), "", "objeto invalid no revienta")
    tvAssertEqual(jsonArray(invalid, "lista").Count(), 0, "array de objeto invalid devuelve []")

    ' user_id: número en unos ISP, texto en otros
    tvAssertEqual(jsonStr(obj, "numero"), "42", "jsonStr acepta un número y lo devuelve como texto")
    tvAssertEqual(jsonInt(obj, "numeroTexto"), 42, "jsonInt acepta un texto numérico")

    ' Booleanos en sus tres formas
    tvAssertEqual(jsonBool(obj, "flagBool"), true, "jsonBool con booleano")
    tvAssertEqual(jsonBool(obj, "flagNum"), true, "jsonBool con 1")
    tvAssertEqual(jsonBool(obj, "flagTexto"), true, "jsonBool con ""true""")
    tvAssertEqual(jsonBool(obj, "noExiste"), false, "jsonBool ausente es false")

    ' Tipo equivocado: no debe colarse ni reventar
    tvAssertEqual(jsonInt(obj, "texto"), 0, "jsonInt sobre texto no numérico cae al fallback")
    tvAssertEqual(jsonArray(obj, "texto").Count(), 0, "jsonArray sobre un texto devuelve []")
end sub
