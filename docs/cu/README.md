# docs/cu — Especificación por Caso de Uso

**Todavía vacío.** Es el siguiente bloque de documentación a escribir, antes de empezar la Fase 1.

Cada archivo `CU-XX-*.md` tendrá, para Roku:

- qué hace (resumen tomado de la spec agnóstica)
- estado que lee y estado que escribe
- algoritmo en pseudocódigo
- **componentes SceneGraph implicados** y en qué Task va la red
- edge cases y **tests Rooibos obligatorios**
- desviaciones respecto al original o al rediseño Kotlin, con su razón

## Mientras tanto, la spec vive fuera

| Fuente | Qué es |
|---|---|
| `../../../app-lg/docs/cu/CU-01..20` | **La spec agnóstica del lenguaje.** Es lo que la app debe hacer |
| `../../../app-lg/docs/cu/MODELS.md`, `STATE.md` | Modelos y estado global del original |
| `../../../app-lg-kotlin-rediseno/docs/cu/CU-01..20` | Cómo se resolvió en Kotlin. **Referencia de solución, no spec** — traen clases Kotlin y dependencias Gradle |

Orden de lectura para implementar un CU: primero el de `app-lg` (qué), después el del Kotlin (cómo).
