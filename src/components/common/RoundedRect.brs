' Rectángulo redondeado. Ver RoundedRect.xml.
'
' ⚠ Toca el dispositivo: no se ejecuta en `npm test`.

sub init()
    m.brand = m.global.brand
    m.fondo = m.top.findNode("fondo")
    onShape()
    onGeometry()
    onColor()
end sub

sub onShape()
    if m.fondo = invalid then return
    if m.top.shape = "pill"
        m.fondo.uri = m.brand.shapePill
    else
        m.fondo.uri = m.brand.shapeCard
    end if
end sub

sub onGeometry()
    if m.fondo = invalid then return
    m.fondo.width = m.top.width
    m.fondo.height = m.top.height
end sub

' La textura es BLANCA: `blendColor` la multiplica y sale del color que toque. Por eso una sola
' imagen por radio vale para toda la app.
sub onColor()
    if m.fondo = invalid then return
    m.fondo.blendColor = m.top.color
end sub
