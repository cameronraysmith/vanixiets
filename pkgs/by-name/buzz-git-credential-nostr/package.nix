# git-credential-nostr - git credential helper issuing Nostr NIP-98 events.
#
# git is deliberately kept out of nativeBuildInputs. The helper shells out to
# `git config` to read nostr.keyfile, and it is referenced only through the
# wrapper, so git is not on PATH during the install check: a dropped wrapper
# fails the build rather than passing by borrowing a git that happened to be
# present.
#
# The install check drives the real credential protocol rather than probing a
# flag. A request consisting of a single newline returns at the
# has_authtype_capability gate (crates/git-credential-nostr/src/lib.rs:160)
# before any key loading is reached, so a check built on that shape would pass
# against a completely broken key path.
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
  pname = "buzz-git-credential-nostr";
  inherit (buzz-source) version cargoDeps;
  src = buzz-source;

  # --bin names the expected binary explicitly. Redundant at this pin, where the
  # crate declares exactly one [[bin]], but it makes an upstream addition of a
  # second binary change the install set visibly instead of silently.
  cargoBuildFlags = [
    "-p"
    "git-credential-nostr"
    "--bin"
    "git-credential-nostr"
  ];

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    wrapProgram $out/bin/git-credential-nostr \
      --prefix PATH : ${lib.makeBinPath [ gitMinimal ]}
  '';

  doCheck = false;

  doInstallCheck = true;
  # The heredoc body and its EOF terminator are indented to the same level as
  # the surrounding shell *in this source file*. Nix strips the common leading
  # indentation, so EOF lands at column 0 in the string that actually runs.
  # Reindenting the whole block uniformly is safe. Dedenting only the terminator
  # is not: the common prefix collapses to zero, nothing is stripped, and the
  # helper receives protocol lines with four leading spaces.
  installCheckPhase = ''
    runHook preInstallCheck

    grep -qF '${gitMinimal}' "$out/bin/git-credential-nostr"

    checkdir=$(mktemp -d)
    printf '%s' 0000000000000000000000000000000000000000000000000000000000000001 \
      > "$checkdir/key"
    chmod 0600 "$checkdir/key"

    # Sectioned form. A sectionless `nostr.keyfile=...` line makes git reject
    # the whole file with "bad config line 1", and git_config maps any
    # non-success exit to None, so the keyfile would silently fail to resolve.
    # This is also the form home-manager renders from programs.git.settings.
    printf '[nostr]\n\tkeyfile = %s\n' "$checkdir/key" > "$checkdir/gitconfig"

    # wwwauth[] advertises the server's Nostr challenge, and the helper only
    # produces a credential in response to one. Omitting the field yields an
    # empty response and a zero exit rather than an error, so the assertions
    # below are what surfaces its absence.
    #
    # The blank line before EOF terminates the credential request. Without it
    # the helper blocks waiting for more input.
    HOME="$checkdir" \
    GIT_CONFIG_NOSYSTEM=1 \
    GIT_CONFIG_GLOBAL="$checkdir/gitconfig" \
      "$out/bin/git-credential-nostr" get > "$checkdir/out" <<'EOF'
    protocol=https
    host=example.communities.buzz.xyz
    path=git
    capability[]=authtype
    wwwauth[]=Nostr realm="buzz", method="GET"

    EOF

    grep -q '^authtype=Nostr$' "$checkdir/out"
    grep -q '^credential=.' "$checkdir/out"

    runHook postInstallCheck
  '';

  meta = {
    homepage = "https://github.com/block/buzz";
    description = "Git credential helper issuing Nostr NIP-98 authorization events";
    changelog = "https://github.com/block/buzz/releases/tag/desktop-v${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "git-credential-nostr";
    maintainers = with lib.maintainers; [ cameronraysmith ];
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
