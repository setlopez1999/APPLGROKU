' Ejecuta una petición HTTP fuera del hilo de render. Ver ApiTask.xml.
'
' ⚠ Toca el dispositivo: no se ejecuta en `npm test`. Verificar en el Roku.

sub init()
    m.top.functionName = "runRequest"
end sub

sub runRequest()
    request = m.top.request
    if request = invalid
        m.top.response = tvHttpResponse(false, 0, "", "petición vacía")
        return
    end if

    port = CreateObject("roMessagePort")
    xfer = tvCreateUrlTransfer(request.url, port)

    ' El User-Agent va SIEMPRE: el servidor de vídeo rechaza con 403 cualquiera que no empiece por
    ' APPMOVIL, y no cuesta nada mandarlo también a la API (docs/BACKEND-GOTCHAS.md §1).
    if request.userAgent <> invalid and request.userAgent <> "" then xfer.AddHeader("User-Agent", request.userAgent)
    if request.contentType <> invalid and request.contentType <> "" then xfer.AddHeader("Content-Type", request.contentType)

    method = "POST"
    if request.method <> invalid and request.method <> "" then method = UCase(request.method)

    ' Casi todo el contrato es POST con los parámetros en el query string y el cuerpo vacío
    ' (docs/BACKEND-GOTCHAS.md §11). No es lo habitual, pero es lo que espera el backend.
    started = false
    if method = "GET"
        started = xfer.AsyncGetToString()
    else
        body = ""
        if request.body <> invalid then body = request.body
        started = xfer.AsyncPostFromString(body)
    end if

    if not started
        m.top.response = tvHttpResponse(false, -1, "", "no se pudo iniciar la petición")
        return
    end if

    timeout = tvApiTimeoutMs()
    if request.timeoutMs <> invalid and request.timeoutMs > 0 then timeout = request.timeoutMs

    msg = wait(timeout, port)

    if msg = invalid
        ' Se agotó el tiempo: hay que cortar, si no el transfer queda vivo.
        xfer.AsyncCancel()
        m.top.response = tvHttpResponse(false, -1, "", "tiempo de espera agotado")
        return
    end if

    if type(msg) <> "roUrlEvent"
        xfer.AsyncCancel()
        m.top.response = tvHttpResponse(false, -1, "", "respuesta inesperada del puerto")
        return
    end if

    code = msg.GetResponseCode()
    body = msg.GetString()
    kind = tvClassifyFailure(code)

    if kind = "ok"
        m.top.response = tvHttpResponse(true, code, body)
    else
        ' Se conserva el cuerpo aunque haya fallado: el backend manda `error:true` con HTTP 200, y en
        ' algún fallo trae detalle útil.
        m.top.response = tvHttpResponse(false, code, body, kind)
    end if
end sub
