' Sonda del DVR. Ver CatchupProbeTask.xml.
'
' ⚠ Toca el dispositivo: no se ejecuta en `npm test`. La construcción de la url y la regla de cuándo
' se ofrece están en domain/usecase/Catchup.brs, que sí tiene tests.

sub init()
    m.top.functionName = "runProbe"
end sub

sub runProbe()
    channels = m.top.channels
    verificados = []

    if channels = invalid
        m.top.verifiedIds = verificados
        return
    end if

    ' Ventana corta y reciente: da igual cuál se pida, el DVR es binario (§4).
    inicio& = tvNowSeconds() - 600

    for each channel in channels
        if channel.catchup = 1 and channel.streamUrl <> ""
            if hasRecording(tvCatchupUrl(channel.streamUrl, inicio&, 60))
                verificados.Push(channel.cnId)
            else
                print "[TV] catchup: el backend marca "; channel.nombre; " pero el DVR no responde"
            end if
        end if
    end for

    print "[TV] catchup verificado en "; verificados.Count(); " canales"
    m.top.verifiedIds = verificados
end sub

' Un 200 NO basta (§4): el manifiesto del DVR puede responder 200 con la chunklist VACÍA, sin un
' solo segmento. Significa que el directorio tiene DVR configurado pero no hay nada grabado, casi
' siempre porque la señal de origen está caída. Un chequeo por código HTTP no lo detecta.
function hasRecording(probeUrl as string) as boolean
    port = CreateObject("roMessagePort")
    xfer = tvCreateUrlTransfer(probeUrl, port)

    ' Sin el User-Agent APPMOVIL, los servidores de Playcom devuelven 403 (§1).
    xfer.AddHeader("User-Agent", tvStreamUserAgent())

    if not xfer.AsyncGetToString() then return false

    msg = wait(tvProbeTimeoutMs(), port)
    if msg = invalid
        xfer.AsyncCancel()
        return false
    end if
    if type(msg) <> "roUrlEvent" then return false
    if msg.GetResponseCode() <> 200 then return false

    ' Con segmentos de verdad la lista trae al menos un #EXTINF.
    return Instr(1, msg.GetString(), "#EXTINF") > 0
end function
