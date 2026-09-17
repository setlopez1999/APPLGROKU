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

## Generar y desplegar

```bash
npm run build:oneplay          # genera src/manifest, BrandConfig y copia las imágenes
npx roku-deploy                # sideload en el Roku de pruebas
telnet <ip-roku> 8085          # consola de depuración, en otra terminal
```

Un ISP nuevo se añade copiando `brands/<isp>/`. Runbook: `docs/MULTI_ISP.md`.
