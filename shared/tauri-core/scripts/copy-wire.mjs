// Copies the wire out of a built @memnox/core into shared/wire: wire.js, wire.d.ts and only the files those two
// import, followed from one to the next. The rest of the core's build is the engine, which this app never runs.
import { copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync } from 'node:fs';
import { dirname, join } from 'node:path';

const [dist, out] = process.argv.slice(2);
if (dist === undefined || out === undefined || !existsSync(join(dist, 'wire.js'))) {
  console.error('usage: copy-wire.mjs <a built core dist holding wire.js> <the folder to fill>');
  process.exit(1);
}

/** A file's relative imports, as the files they name on disk: a declaration imports `./x.js` and means `./x.d.ts`. */
function imports(file) {
  const declares = file.endsWith('.d.ts');
  const found = [];
  for (const [, named] of readFileSync(join(dist, file), 'utf8').matchAll(/from\s*['"]\.\/([^'"]+)['"]/g)) {
    found.push(declares ? named.replace(/\.js$/, '.d.ts') : named);
  }
  return found;
}

const wanted = new Set();
const queue = ['wire.js', 'wire.d.ts'];
while (queue.length > 0) {
  const file = queue.pop();
  if (wanted.has(file)) continue;
  if (!existsSync(join(dist, file))) {
    console.error(`the wire imports ${file}, which ${dist} does not hold`);
    process.exit(1);
  }
  wanted.add(file);
  queue.push(...imports(file));
}

// What a person wrote beside the copy stays; every file of an earlier copy goes, since a chunk's name changes with its bytes.
mkdirSync(out, { recursive: true });
for (const old of readdirSync(out)) {
  if (old.endsWith('.js') || old.endsWith('.d.ts')) rmSync(join(out, old));
}
for (const file of [...wanted].sort()) {
  mkdirSync(dirname(join(out, file)), { recursive: true });
  copyFileSync(join(dist, file), join(out, file));
}
console.log([...wanted].sort().join('\n'));
