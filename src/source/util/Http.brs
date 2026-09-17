' Construcción de peticiones HTTP. Fábrica ÚNICA de `roUrlTransfer`.
'
' ⚠ Esta capa toca el dispositivo: no se puede ejecutar en `npm test` (el intérprete de Node no
' implementa `roUrlTransfer`). Solo la valida el compilador. Verificar en el Roku.
'
' Por qué una fábrica única y nadie crea un roUrlTransfer a mano (docs/ROKU-GOTCHAS.md §1):
' en BrightScript, HTTPS **falla sin el archivo de certificados**. Y no falla con un mensaje claro:
' se parece a un problema de red o del backend. Un solo sitio donde ponerlo = imposible olvidarlo.

' El servidor de vídeo devuelve 403 a cualquier User-Agent que no empiece por APPMOVIL
' (docs/BACKEND-GOTCHAS.md §1). Sin esto, todo el vídeo sale negro y no hay error que lo explique.
' La API (:443) NO lo exige; solo el vídeo (:1936). Mandarlo siempre es seguro para ambos.
function tvStreamUserAgent() as string
    return "APPMOVIL-roku"
end function

function tvApiTimeoutMs() as integer
    return 15000
end function

' Sonda del DVR: corta a propósito. Solo interesa si el directorio graba o no (§4, es binario).
function tvProbeTimeoutMs() as integer
    return 8000
end function

function tvCreateUrlTransfer(url as string, port as object) as object
    xfer = CreateObject("roUrlTransfer")
    xfer.SetUrl(url)
    xfer.SetMessagePort(port)

    ' Obligatorio para HTTPS. Sin estas dos líneas no hay una sola llamada que funcione.
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.InitClientCertificates()

    ' Sigue redirecciones: algunos ISP mueven el stream de servidor con un 302.
    xfer.EnableEncodings(true)
    return xfer
end function

' Petición a la API. El User-Agent aquí da igual, pero mandarlo no molesta y evita despistes.
function tvApiRequest(url as string, method = "POST" as string, body = "" as string) as object
    return {
        url: url
        method: method
        body: body
        timeoutMs: tvApiTimeoutMs()
        contentType: "application/json"
        userAgent: tvStreamUserAgent()
    }
end function

' Respuesta normalizada, para que quien la consume no dependa de la forma de `roUrlEvent`.
function tvHttpResponse(ok as boolean, statusCode as integer, body as string, errorMessage = "" as string) as object
    json = invalid
    if body <> "" then json = ParseJson(body)
    return {
        ok: ok
        statusCode: statusCode
        body: body
        json: json
        error: errorMessage
    }
end function

' Distingue los tres fallos que un "¿responde 200?" confunde (docs/BACKEND-GOTCHAS.md §8):
'   "tls"      la conexión ni se establece → certificado o SNI (nos pasó con un cert vencido:
'              5 canales parecían caídos y emitían perfecto)
'   "notfound" 404 → la ruta no existe o el stream no está publicado
'   "ok"       200
'   "http"     cualquier otro código
function tvClassifyFailure(statusCode as integer) as string
    if statusCode = 200 then return "ok"
    if statusCode = 404 then return "notfound"
    ' roUrlTransfer usa códigos negativos para los fallos de transporte (TLS, DNS, timeout).
    if statusCode < 0 then return "tls"
    return "http"
end function
