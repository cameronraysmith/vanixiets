# git-sign-nostr - NIP-GS git object signing program for gpg.x509.program.
#
# Nothing in this repository wires this package. Git resolves gpg.format
# globally with no URL scoping, and modules/home/development/git.nix:20-28
# already sets SSH signing with signByDefault, so wiring it would replace SSH
# signing everywhere rather than adding a capability. It ships for
# per-repository opt-in; see NOTES.md for the recipe.
#
# The git wrapper is mandatory rather than a convenience, on two paths. The
# keyfile is read through `git config nostr.keyfile`, and load_auth_tag reads
# nostr.authtag through git_config_strict, which fails closed when the spawn
# itself fails. The auth-tag path is reached only when BUZZ_AUTH_TAG is unset or
# empty, since a non-empty value short-circuits the git call
# (crates/git-sign-nostr/src/lib.rs:467-475).
#
# meta.platforms is unix-only because the program passes status output over an
# inherited file descriptor selected by --status-fd
# (crates/git-sign-nostr/src/lib.rs:6).
#
# Source: https://github.com/block/buzz
{
  lib,
  rustPlatform,
  buzz-source,
  makeWrapper,
  gitMinimal,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "buzz-git-sign-nostr";
  inherit (buzz-source) version cargoDeps;
  src = buzz-source;

  # --bin names the expected binary explicitly. Redundant at this pin, where the
  # crate declares exactly one [[bin]], but it makes an upstream addition of a
  # second binary change the install set visibly instead of silently.
  cargoBuildFlags = [
    "-p"
    "git-sign-nostr"
    "--bin"
    "git-sign-nostr"
  ];

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    wrapProgram $out/bin/git-sign-nostr \
      --prefix PATH : ${lib.makeBinPath [ gitMinimal ]}
  '';

  doCheck = false;

  doInstallCheck = true;
  # Sign then verify what was just signed. This exercises the signing path,
  # which is the program's primary function, and proves the git wrapper twice
  # over: the key is delivered through `git config nostr.keyfile` rather than an
  # environment variable, and load_auth_tag then consults nostr.authtag.
  #
  # The key arrives as a keyfile on purpose. The NOSTR_PRIVATE_KEY path would
  # skip open_keyfile entirely, and open_keyfile's symlink, mode and uid gates
  # are exactly what the sops wiring depends on.
  #
  # --status-fd=2 on sign is explicit rather than incidental: passing 1 there
  # would corrupt the armor on stdout, so the program rewrites it to 2 and warns
  # (lib.rs:1741-1747). Relying on that fallback would make the check depend on
  # a recovery path instead of stating the intent.
  #
  # BUZZ_AUTH_TAG is unset explicitly. A non-empty value short-circuits the
  # git_config_strict call, which would leave this check green with a dropped
  # wrapper — the one failure it exists to catch.
  #
  # The -bsau argument is the public key tabulated for this secret in
  # docs/nips/NIP-GS.md:644-645, so signing asserts key derivation against a
  # value the binary did not produce. An empty argument would also sign, since
  # do_sign compares it against the loaded key only when non-empty
  # (crates/git-sign-nostr/src/lib.rs:977-997); the quotes around it would then
  # be load-bearing, as -bsau consumes the next argument.
  #
  # GOODSIG alone would not prove the wrapper. Verification is cryptographically
  # self-contained — it reads the pubkey out of the envelope and never spawns
  # git — so that assertion passes identically with or without the wrapper.
  # TRUST_FULLY is the one that carries severity on the verify side:
  # determine_trust emits it only when `git config user.signingkey` normalizes
  # to the envelope pubkey, and degrades silently to TRUST_UNDEFINED when the
  # git spawn fails (lib.rs:1673-1682). Silent degradation is the verify-side
  # analogue of the credential helper's silent misdirection, whereas the sign
  # side fails loudly through git_config_strict. Asserting both covers both
  # shapes, and the wrapper is then proven on three independent paths: keyfile
  # lookup, auth-tag lookup, and trust determination.
  installCheckPhase = ''
    runHook preInstallCheck

    checkdir=$(mktemp -d)

    # Shaped like a git commit object, which is what the program signs in use.
    # The tree is git's empty-tree hash.
    cat > "$checkdir/payload" <<'PAYLOAD'
    tree 4b825dc642cb6eb9a060e54bf8d69288fbee4904
    author Install Check <check@example.invalid> 1700000000 +0000
    committer Install Check <check@example.invalid> 1700000000 +0000

    buzz git-sign-nostr install check
    PAYLOAD

    # Owner secret from docs/nips/NIP-GS.md:644, whose pubkey is tabulated on
    # the following line. A published test vector, never a real signing key.
    printf '%s' 0000000000000000000000000000000000000000000000000000000000000001 \
      > "$checkdir/key"
    chmod 0600 "$checkdir/key"

    pk=79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798

    # user.signingkey is what determine_trust reads; without it the verify step
    # would emit TRUST_UNDEFINED and assert nothing about the wrapper.
    printf '[nostr]\n\tkeyfile = %s\n[user]\n\tsigningkey = %s\n' \
      "$checkdir/key" "$pk" > "$checkdir/gitconfig"

    unset BUZZ_AUTH_TAG
    export HOME="$checkdir"
    export GIT_CONFIG_NOSYSTEM=1
    export GIT_CONFIG_GLOBAL="$checkdir/gitconfig"

    "$out/bin/git-sign-nostr" --status-fd=2 -bsau "$pk" \
      < "$checkdir/payload" > "$checkdir/sig.asc"

    # Armor shape, asserted before verifying. parse_armor requires exactly three
    # lines and a trailing newline; without this assertion a malformed envelope
    # surfaces as "signature invalid" and points at the crypto rather than the
    # formatter.
    [ "$(wc -l < "$checkdir/sig.asc")" -eq 3 ]
    [ -z "$(tail -c 1 "$checkdir/sig.asc")" ]

    "$out/bin/git-sign-nostr" --status-fd=1 --verify "$checkdir/sig.asc" - \
      < "$checkdir/payload" > "$checkdir/status"
    grep -q "^\[GNUPG:\] GOODSIG $pk $pk\$" "$checkdir/status"
    grep -q '^\[GNUPG:\] TRUST_FULLY ' "$checkdir/status"

    # A non-zero exit alone would be satisfied by any unrelated failure — a
    # missing file, a bad path, a sandbox permissions problem. Asserting BADSIG
    # and the absence of GOODSIG pins the outcome from both directions, so the
    # case proves the signature was rejected rather than that something went
    # wrong. Emission is at lib.rs:1234-1235.
    #
    # Both absence checks use `if ... then exit 1; fi` rather than `! grep`.
    # Under set -e the shell does not exit when a command's status is inverted
    # with `!`, so `! grep -q GOODSIG` would pass silently in exactly the case
    # it exists to catch.
    sed 's/install check/install check tampered/' "$checkdir/payload" \
      > "$checkdir/payload.bad"
    if "$out/bin/git-sign-nostr" --status-fd=1 --verify "$checkdir/sig.asc" - \
      < "$checkdir/payload.bad" > "$checkdir/status.bad"; then
      echo "error: verification succeeded against a tampered payload" >&2
      exit 1
    fi
    grep -q "^\[GNUPG:\] BADSIG $pk $pk\$" "$checkdir/status.bad"
    if grep -q '^\[GNUPG:\] GOODSIG ' "$checkdir/status.bad"; then
      echo "error: tampered payload still produced GOODSIG" >&2
      exit 1
    fi

    runHook postInstallCheck
  '';

  meta = {
    homepage = "https://github.com/block/buzz";
    description = "NIP-GS git commit/tag signing program using Nostr secp256k1 keys";
    changelog = "https://github.com/block/buzz/releases/tag/desktop-v${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "git-sign-nostr";
    maintainers = with lib.maintainers; [ cameronraysmith ];
    platforms = lib.platforms.unix;
  };
})
