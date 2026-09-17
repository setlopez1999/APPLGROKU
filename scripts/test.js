#!/usr/bin/env node
/**
 * Ejecuta los tests de la capa de lógica en Node con `brs`, sin Roku.
 *
 * Esto solo es posible porque `domain/` y `data/` son BrightScript puro, sin nodos SceneGraph
 * (regla de capas de AGENTS.md). Si algún día un test necesita un nodo, la pieza está en la capa
 * equivocada.
 *
 * Uso: npm test
 */

const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');

// Orden: primero el código bajo prueba, luego el arnés y las fixtures, y `run.brs` al final
// (es quien tiene el main()).
const sources = [
  ...walk(path.join(ROOT, 'src', 'source', 'util')),
  ...walk(path.join(ROOT, 'src', 'source', 'domain')),
  ...walk(path.join(ROOT, 'src', 'source', 'data')),
].filter((f) => f.endsWith('.brs'));

const testsDir = path.join(ROOT, 'tests');
const harness = ['_harness.brs', '_fixtures.brs'].map((f) => path.join(testsDir, f));
const suites = fs
  .readdirSync(testsDir)
  .filter((f) => f.endsWith('_test.brs'))
  .sort()
  .map((f) => path.join(testsDir, f));

const files = [...sources, ...harness, ...suites, path.join(testsDir, 'run.brs')];

const result = spawnSync('npx', ['brs', ...files.map((f) => path.relative(ROOT, f))], {
  cwd: ROOT,
  stdio: 'inherit',
  shell: true,
});

process.exit(result.status === null ? 1 : result.status);

function walk(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir).flatMap((entry) => {
    const full = path.join(dir, entry);
    return fs.statSync(full).isDirectory() ? walk(full) : [full];
  });
}
