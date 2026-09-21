# TV-Visor — Canal Roku

Canal de Roku (BrightScript + SceneGraph) de TV-Visor: IPTV multi-ISP con canales en vivo, EPG,
catch-up, favoritos, control parental y multi-CDN.

- **Diseño**: réplica del rediseño Kotlin (`../app-lg-kotlin-rediseno`, rama `NORETURNOVERLAYNEWFLOW`).
- **Funcionalidad**: paridad con el original (`../app-lg`), los 20 casos de uso.
- **Estado**: Fase 0 — esqueleto y documentación. Sin código de negocio.

## Por dónde empezar

1. `docs/BACKEND-GOTCHAS.md` — trampas del backend verificadas en producción. **Antes que nada.**
2. `AGENTS.md` — reglas del repo, jerarquía de fuentes de verdad, metodología.
3. `docs/PLAN.md` — plan maestro y orden de construcción.
4. `docs/DISENO.md` — la especificación visual (el objetivo del proyecto).

## Sin Roku (en el PC)

```bash
npm install
npm test                       # tests de la lógica — corren en Node, sin dispositivo
npm run lint                   # valida todo el proyecto con el compilador

# Diagnóstico de streams: ¿este canal entrega vídeo de verdad?
npm run audit -- --host <host> --user <email> --pass <clave> --catchup
npm run audit -- --url "https://host:1936/dir/canal.stream/playlist.m3u8"
```

**No hay emulador de Roku.** Para ver el canal hace falta un aparato físico; qué se puede probar sin
él y qué no está en `docs/PLAN.md` §9.0.

## Cambiar de ISP

Toda la identidad del cliente vive en `brands/<isp>/`. Es el equivalente de los product flavors del
proyecto Kotlin: **no se toca una línea de código para cambiar de cliente**.

```bash
# ciclo completo en un Roku real: genera marca, empaqueta, instala, lanza y vuelca la consola
HOST=192.168.0.203 PASS=<clave-dev> sh scripts/dev-cycle.sh oneplay
HOST=192.168.0.203 PASS=<clave-dev> sh scripts/dev-cycle.sh playcom

# o por partes
npm run build:playcom && npm run package
```

ISPs registrados: `oneplay` (no exige el User-Agent APPMOVIL) y `playcom` (**sí lo exige**: devuelve
403 sin él). Añadir uno nuevo: copiar la carpeta y rellenar `config.txt` — ver `docs/MULTI_ISP.md`.

## Generar el paquete para probar en un Roku

```bash
npm run build:oneplay          # genera src/manifest, BrandConfig y copia las imágenes
npm run package                # deja out/applg-roku.zip listo para instalar
```

El `.zip` que sale es el canal completo. Se instala en cualquier Roku en modo desarrollador, y
**no hace falta esta máquina**: basta con pasarle el archivo a quien tenga el aparato.

### Cómo lo instala quien tenga el Roku

1. **Activar el modo desarrollador** en el Roku, con el mando:
   `Inicio ×3, Arriba ×2, Derecha, Izquierda, Derecha, Izquierda, Derecha`
   Aparece una pantalla: aceptar, poner una contraseña y dejar que reinicie. Anotar la **IP** que
   muestra.
2. Desde un ordenador **en la misma red**, abrir en el navegador `http://<ip-del-roku>/`
   Pide usuario `rokudev` y la contraseña del paso 1.
3. Subir `applg-roku.zip` y pulsar **Replace** / **Install**.
4. El canal aparece en la pantalla de inicio del Roku.

Para ver los errores mientras corre: `telnet <ip-del-roku> 8085` desde otra terminal.

### Qué se verá

La pantalla de login del ISP configurado en `brands/<isp>/config.txt`. Para pasar de ahí hace falta
una **cuenta real de ese ISP**. Las imágenes son placeholders de color sólido
(`npm run images:oneplay`) hasta que llegue el arte definitivo.

### Sideload directo por red (si el Roku está a mano)

```bash
npx roku-deploy                # necesita la IP y la contraseña en bsconfig.json
```

Un ISP nuevo se añade copiando `brands/<isp>/`. Runbook: `docs/MULTI_ISP.md`.
