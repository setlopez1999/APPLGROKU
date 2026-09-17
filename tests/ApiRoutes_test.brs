sub testApiRoutes()
    tvSuite("data/remote/ApiRoutes — contrato del backend (BACKEND-GOTCHAS §11 y §12)")

    base = "https://isp.cd-latam.com/"

    ' Login: sin token. Platform 12 = Roku (ya estaba en el enum OS del original).
    login = tvApiGetWeb2Url(base, "demo@isp.tv", "clave123", "1234567890", 12)
    tvAssertEqual(login, "https://isp.cd-latam.com/api/get-web2?user=demo%40isp.tv&pass=clave123&devid=1234567890&platform=12", "url de login con platform 12")

    ' Revalidación: el MISMO endpoint, con token, y el password otra vez en claro (§11).
    reval = tvApiGetWeb2Url(base, "demo@isp.tv", "clave123", "1234567890", 12, "tok-abc")
    tvAssert(Instr(1, reval, "&token=tok-abc") > 0, "la revalidación añade el token")
    tvAssert(Instr(1, reval, "pass=clave123") > 0, "y sigue mandando el password, no solo el token")

    tvAssertEqual(tvApiEpgGuideUrl(base, "demo@isp.tv"), "https://isp.cd-latam.com/api/get-epgguide?user=demo%40isp.tv", "url de la guía")
    tvAssertEqual(tvApiGetFavoritesUrl(base, "demo@isp.tv"), "https://isp.cd-latam.com/api/get-favorite?user_email=demo%40isp.tv", "url de favoritos")
    tvAssertEqual(tvApiAddFavoriteUrl(base, "demo@isp.tv", 101), "https://isp.cd-latam.com/api/set-favorite?user_email=demo%40isp.tv&channel_id=101", "añadir favorito")
    tvAssertEqual(tvApiDeleteFavoriteUrl(base, "demo@isp.tv", 101), "https://isp.cd-latam.com/api/delete-favorite?user_email=demo%40isp.tv&channel_id=101", "quitar favorito (POST, no DELETE)")
    tvAssertEqual(tvApiDesvincularUrl(base, "tok-abc"), "https://isp.cd-latam.com/api/desvincular?token=tok-abc", "desvincular lleva el token en el query, sin body")
    tvAssertEqual(tvApiDashboardUrl(base, "tok-abc", 101), "https://isp.cd-latam.com/tok-abc/101.json", "heartbeat es {token}/{cn_id}.json")

    ' El body de la restricción por IP: {ip, cn_id}
    body = tvApiChannelAllowedIpBody("200.100.50.25", 101)
    tvAssert(Instr(1, body, """ip""") > 0, "el body de restricción lleva ip")
    tvAssert(Instr(1, body, """cn_id""") > 0, "y cn_id (no channel_id)")

    ' Multi-CDN: deviceid siempre 1, está fijo en el original
    cdnBody = tvApiMultiCdnBody("200.100.50.25")
    tvAssert(Instr(1, cdnBody, """deviceid""") > 0, "el body de multi-CDN lleva deviceid")
    tvAssert(Instr(1, cdnBody, """networkid""") > 0, "y networkid con la IP")

    tvSuite("ApiRoutes — bases con y sin barra, y escapado")

    tvAssertEqual(tvJoinUrl("https://isp.tv", "api/x"), "https://isp.tv/api/x", "base sin barra final")
    tvAssertEqual(tvJoinUrl("https://isp.tv/", "api/x"), "https://isp.tv/api/x", "base con barra final no duplica")
    tvAssertEqual(tvJoinUrl("https://isp.tv/", "/api/x"), "https://isp.tv/api/x", "ruta con barra inicial tampoco")

    ' Esto importa de verdad: una contraseña con símbolos sin escapar rompe el query string y el
    ' usuario ve "credenciales incorrectas" con la clave correcta.
    tvAssertEqual(tvUrlEncode("a&b"), "a%26b", "el & se escapa")
    tvAssertEqual(tvUrlEncode("a+b"), "a%2Bb", "el + se escapa (si no, llega como espacio)")
    tvAssertEqual(tvUrlEncode("a b"), "a%20b", "el espacio se escapa")
    tvAssertEqual(tvUrlEncode("p@ss#1"), "p%40ss%231", "arroba y almohadilla se escapan")
    tvAssertEqual(tvUrlEncode("aA9-_.~"), "aA9-_.~", "los caracteres no reservados se dejan tal cual")
    tvAssertEqual(tvUrlEncode(""), "", "cadena vacía")

    conSimbolos = tvApiGetWeb2Url("https://isp.tv/", "a b@isp.tv", "p@ss&1", "123", 12)
    tvAssert(Instr(1, conSimbolos, "pass=p%40ss%261") > 0, "la contraseña con símbolos viaja escapada")
end sub
