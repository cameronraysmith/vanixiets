// Write the openspec-* skills a pinned OpenSpec package generates, offline.
//
// Usage: node generate-skills.mjs <package-root> <out-dir> <version>
//
// <package-root> is the installed @fission-ai/openspec directory. Its
// `expectedSkillContents` is the function `openspec init` uses to verify the
// skills it fetches from GitHub (Fission-AI/OpenSpec#2241), so this produces
// the same bytes without network access. It is internal, not a public API, so a
// missing module fails naming the file it expected.
//
// Shared by modules/apps/openspec-refresh-vendored-artifacts.sh, which vendors
// the output, and the openspec-vendored-skills check, which compares the
// vendored copies against it.
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const [root, out, version] = process.argv.slice(2);
if (!root || !out || !version) {
  console.error('usage: generate-skills.mjs <package-root> <out-dir> <version>');
  process.exit(2);
}

const module = join(root, 'dist', 'core', 'skill-installer.js');
if (!existsSync(module)) {
  console.error(`error: ${module} does not exist; OpenSpec ${version} moved expectedSkillContents`);
  process.exit(1);
}
const { expectedSkillContents } = await import(pathToFileURL(module).href);
if (typeof expectedSkillContents !== 'function') {
  console.error(`error: ${module} no longer exports expectedSkillContents (OpenSpec ${version})`);
  process.exit(1);
}

for (const [name, text] of expectedSkillContents(version)) {
  mkdirSync(join(out, name), { recursive: true });
  writeFileSync(join(out, name, 'SKILL.md'), text);
}
