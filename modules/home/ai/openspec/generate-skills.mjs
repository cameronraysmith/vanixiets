// Write the openspec-* skills a pinned OpenSpec package generates, offline.
//
// Usage: node generate-skills.mjs <package-root> <out-dir> <version>
//
// <package-root> is the installed @fission-ai/openspec directory. Its
// `expectedSkillFiles` returns every file of each skill the release installs
// (SKILL.md and, for the `openspec` skill, its references/*.md), the same map
// `openspec init` and `openspec update` install from, so this produces the
// bytes they would install without running them. It is internal, not a public
// API, so a missing module fails naming the file it expected.
//
// Shared by modules/apps/openspec-refresh-vendored-artifacts.sh, which vendors
// the output, and the openspec-vendored-skills check, which compares the
// vendored copies against it.
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { pathToFileURL } from 'node:url';

const [root, out, version] = process.argv.slice(2);
if (!root || !out || !version) {
  console.error('usage: generate-skills.mjs <package-root> <out-dir> <version>');
  process.exit(2);
}

const module = join(root, 'dist', 'core', 'skill-installer.js');
if (!existsSync(module)) {
  console.error(`error: ${module} does not exist; OpenSpec ${version} moved expectedSkillFiles`);
  process.exit(1);
}
const { expectedSkillFiles } = await import(pathToFileURL(module).href);
if (typeof expectedSkillFiles !== 'function') {
  console.error(`error: ${module} no longer exports expectedSkillFiles (OpenSpec ${version})`);
  process.exit(1);
}

for (const [name, files] of expectedSkillFiles(version)) {
  for (const [file, text] of files) {
    const target = join(out, name, file);
    mkdirSync(dirname(target), { recursive: true });
    writeFileSync(target, text);
  }
}
