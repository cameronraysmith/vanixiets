import assert from "node:assert/strict";

export function gateIdentityText(gate) {
  switch (gate.kind) {
    case "NixEval": return gate.target.kind === "Expr" ? gate.target.expr : gate.target.attr;
    case "Command": return gate.argv.join("\n");
    case "GrepAssert": return `${gate.file}\n${gate.pattern}`;
    case "NixBuildRemote": return gate.installable;
    default: throw new Error(`Unsupported identity gate kind: ${gate.kind}`);
  }
}

export function assertSlicePositions(slices) {
  for (const [index, slice] of slices.entries()) assert.equal(slice.id, index, `slices[${index}].id must equal ${index}`);
}

export function assertGateIdentity(ref, slices) {
  const label = `${ref.slice}:${ref.index} identity does not describe its gate: ${ref.identity}`;
  const tokens = [...ref.identity.matchAll(/`([^`]+)`/g)].map((match) => match[1]);
  assert(tokens.length > 0 && tokens.every((token) => token.length >= 8 && /[._/=:?-]/.test(token)), `${label}; quote technical selectors, paths or predicates in backticks`);
  const matches = (gate) => tokens.every((token) => gateIdentityText(gate).includes(token));
  assert(matches(ref.gate), `${label}; missing ${JSON.stringify(tokens.filter((token) => !gateIdentityText(ref.gate).includes(token)))}`);
  const alternatives = slices[ref.slice].gates.filter((gate) => gate.kind === ref.gate.kind && matches(gate));
  assert(alternatives.every((gate) => JSON.stringify(gate) === JSON.stringify(ref.gate)), `${label}; anchors also match a different gate in S${ref.slice}`);
  return tokens;
}

export function runIdentityChecks({ slices, joinGateSupersessions }, { audit = false } = {}) {
  assertSlicePositions(slices);
  assert.equal(joinGateSupersessions.length, 33);
  for (const entry of joinGateSupersessions) {
    for (const ref of [entry.superseded, entry.superseding]) {
      assert.equal(slices[ref.slice].gates[ref.index], ref.gate);
      assertGateIdentity(ref, slices);
    }
    if (audit) console.log("IDENTITY AUDIT", JSON.stringify({ ...entry, identityDescribesBoth: true, verdict: "pass" }));
  }
  console.log(`PASS identity anchors: ${joinGateSupersessions.length} supersessions, ${joinGateSupersessions.length * 2} endpoints; all slice IDs equal positions: ${slices.map((slice) => slice.id).join(",")}`);

  const disputed = joinGateSupersessions.find(({ superseded }) => superseded.slice === 4 && superseded.index === 1).superseding;
  const corrupt = { ...disputed, index: 7, gate: slices[10].gates[7] };
  assert(corrupt.identity && slices[corrupt.slice].gates[corrupt.index] === corrupt.gate, "The old assertion accepts the corrupted reference");
  assert.throws(() => assertGateIdentity(corrupt, slices), (error) => {
    assert.match(error.message, /10:7 identity does not describe its gate/);
    console.log(`PASS deliberate index corruption S10:3 -> S10:7: old assertion passes; new assertion rejects: ${error.message}`);
    return true;
  });
  assert.throws(() => assertGateIdentity({ ...disputed, identity: "the `magnetite`" }, slices), /quote technical selectors/);
  assert.throws(() => assertGateIdentity({ ...disputed, identity: "Generic `builtins.getFlake`" }, slices), /anchors also match a different gate/);
  assert.throws(() => assertSlicePositions(slices.map((slice, index) => index === 10 ? { ...slice, id: 9 } : slice)), /slices\[10\].id/);

  for (const [gate, wrong, identity] of [
    [{ kind: "Command", argv: ["bash", "-c", "probe --declared-host magnetite"] }, { kind: "Command", argv: ["bash", "-c", "probe --server-url pyrite"] }, "Runner `--declared-host`"],
    [{ kind: "GrepAssert", file: "runner.nix", pattern: "settings\\.host\\.name" }, { kind: "GrepAssert", file: "runner.nix", pattern: "serverUrl" }, "Runner `runner.nix` declares `settings\\.host\\.name`"],
    [{ kind: "NixBuildRemote", installable: "source#checks.x86_64-linux.nixos-magnetite" }, { kind: "NixBuildRemote", installable: "source#checks.x86_64-linux.nixos-pyrite" }, "Closure `checks.x86_64-linux.nixos-magnetite`"],
    [{ kind: "NixEval", target: { kind: "Attr", attr: "source#packages.x86_64-linux.omnigent.version" } }, { kind: "NixEval", target: { kind: "Attr", attr: "source#packages.aarch64-darwin.omnigent.version" } }, "Version `packages.x86_64-linux.omnigent.version`"],
  ]) {
    const fixture = [{ id: 0, gates: [gate, wrong] }];
    assertGateIdentity({ slice: 0, index: 0, identity, gate }, fixture);
    assert.throws(() => assertGateIdentity({ slice: 0, index: 1, identity, gate: wrong }, fixture), /identity does not describe its gate/);
  }
  console.log("PASS identity negative controls: stopword, shared boilerplate, slice-position drift, Command argv, GrepAssert file/pattern, NixBuildRemote installable and NixEval Attr target");
  if (audit) console.log(`S10:3 VERBATIM EXPRESSION\n${slices[10].gates[3].target.expr}`);
}
