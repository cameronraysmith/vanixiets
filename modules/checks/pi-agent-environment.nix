# Three independent regulators for the Pi coding-agent environment.
#
# pi-agent-environment-structural, -policy and -smoke are separate derivations
# with independent cache boundaries; co-location here groups related definitions
# and nothing more. See D8 in
# openspec/changes/archive/2026-08-15-configure-pi-agent-environment/design.md
# for the decision record, kept there rather than restated here so a second copy
# cannot drift from the first.
#
# Mechanism per check:
#   structural  mkStructuralCheck diffs eval-time home-manager values against a
#               literal oracle. modules/lib/mk-eval-check.nix routes assertions
#               that need full flake evaluation away from nix-unit, so a
#               runCommand JSON diff is the available shape for these.
#   policy      runCommand typechecks the deployed policy sources with tsc, then
#               drives the case table through the pinned permission-gate parser
#               under bun. No Pi process runs per row.
#   smoke       runCommand drives one deployed Pi wrapper over RPC in a hermetic
#               $TMPDIR home.
#
# jj argv is asserted exactly rather than by outcome: a probe that silently
# snapshotted the working copy would still return the correct decision, so
# read-only-ness is observable only in the argument vector.
#
# Evidence boundary. Structural evidence claims declaration shape alone, not
# runtime loading, live writability, upstream provenance from package metadata,
# or package-output behavior. The "exactly one by-name package, no flake input"
# claim comes from a separate pre-activation scope-and-diff scan, not from here,
# and the theme digest proves checked-in content identity, not upstream fetch.
# Smoke claims only successful get_state and get_commands responses, no
# extension_error record, the synthetic smoke-local/smoke-model selection, and a
# clean exit; its fixture never installs edit-write-policy.ts into the agent
# extensions directory, so no check here covers that adapter registering against
# a live host.
#
# Falsifiability: dropping a positive selector from modules/home/ai/pi/default.nix
# flips actual.positiveExtensions against the six-path literal in the expected
# attrset below.
#
# The decomposed conjuncts (contextNixOwned, immutableResourceTargets.*) are
# per-claim diff granularity, not redundancy: a failure names the violated claim
# instead of collapsing to one aggregate boolean.
{ self, lib, ... }:
{
  perSystem =
    {
      pkgs,
      self',
      system,
      ...
    }:
    let
      mkCheck = self.lib.mkStructuralCheck pkgs;
      piModuleText = builtins.readFile ../home/ai/pi/default.nix;
      # Anchored so a version-shaped 0.83 is distinguished from an incidental
      # digit run: 10.83, 0.830 and 20.83% must not count as references.
      pi083Pattern = "(.*[^0-9])?0\\.83([^0-9].*)?";
      pi083References =
        text:
        lib.pipe (lib.splitString "\n" text) [
          (lib.imap1 (index: line: { inherit index line; }))
          (builtins.filter (entry: builtins.match pi083Pattern entry.line != null))
          (map (entry: "${toString entry.index}: ${entry.line}"))
        ];
      # docs/notes/ is a lifecycle-managed working-notes tree, so guard the read:
      # builtins.readFile on a missing path aborts evaluation of the whole check.
      piReconnaissancePath = ../../docs/notes/development/ai-agents/pi-integration-reconnaissance.md;
      piReconnaissancePresent = builtins.pathExists piReconnaissancePath;
      piReconnaissanceText =
        if piReconnaissancePresent then builtins.readFile piReconnaissancePath else "";
      homeConfig = self.homeConfigurations."crs58@${system}".config;
      piConfig = homeConfig.programs.pi-coding-agent;
      extensionPackage = self'.packages.pi-agent-extensions or null;
      extensionSource = if extensionPackage == null then null else toString extensionPackage;
      compactionPackage = self'.packages.pi-openai-server-compaction or null;
      compactionSource = if compactionPackage == null then null else toString compactionPackage;
      vimPackage = self'.packages.pi-vim or null;
      vimSource = if vimPackage == null then null else toString vimPackage;
      packageEntries = piConfig.settings.packages or [ ];
      extensionEntry = lib.findFirst (
        entry: builtins.isAttrs entry && (entry.source or null) == extensionSource
      ) null packageEntries;
      extensionSelectors = if extensionEntry == null then [ ] else extensionEntry.extensions or [ ];
      positiveExtensions = builtins.filter (selector: !lib.hasPrefix "-" selector) extensionSelectors;
      negativeExtensions = builtins.filter (selector: lib.hasPrefix "-" selector) extensionSelectors;
      extensionSourceImmutable =
        extensionEntry != null && lib.hasPrefix builtins.storeDir (toString extensionEntry.source);
      homeFileAt = target: lib.attrByPath [ target ] null homeConfig.home.file;
      homeFileEnabled =
        target:
        let
          file = homeFileAt target;
        in
        file != null && file.enable;
      homeFileImmutable =
        target:
        let
          file = homeFileAt target;
        in
        file != null
        && file.enable
        && file.source != null
        && lib.hasPrefix builtins.storeDir (toString file.source);
      homeFileSourceIs =
        target: expected:
        let
          file = homeFileAt target;
        in
        file != null && file.source != null && toString file.source == toString expected;
      hasImmutableHomeFileAtOrBelow =
        target:
        lib.any (name: (name == target || lib.hasPrefix "${target}/" name) && homeFileImmutable name) (
          builtins.attrNames homeConfig.home.file
        );
      settingsTarget = "${piConfig.configDir}/settings.json";
      sessionsTarget = "${piConfig.configDir}/sessions";
      authenticationTarget = "${piConfig.configDir}/auth.json";
      projectTrustTarget = "${piConfig.configDir}/trust.json";
      extensionStateTarget = "${piConfig.configDir}/packages";
      settingsActivation = lib.attrByPath [
        "piCodingAgentMutableSettings"
      ] { } homeConfig.home.activation;
      settingsActivationData = settingsActivation.data or "";
      # These stay total and defer their diagnostics to build-time guards in the
      # smoke check: a `throw` here aborts evaluation of the whole flake-check
      # set, which would preempt the structural check's readable diff.
      deployedPiCandidates = builtins.filter (
        package: (package.meta.mainProgram or null) == "pi"
      ) homeConfig.home.packages;
      deployedPiPackage =
        if builtins.length deployedPiCandidates == 1 then builtins.head deployedPiCandidates else null;
      deployedPiIsOuterWrapper =
        deployedPiPackage != null && toString deployedPiPackage != toString piConfig.package;
      deployedPiExecutable = if deployedPiIsOuterWrapper then lib.getExe deployedPiPackage else "";
      requiredHomeFileSource =
        target: if homeFileImmutable target then (homeFileAt target).source else null;
      # Pi persists several runtime-state categories into one file: settings.json
      # takes model selection, thinking preferences, and `pi install` extension
      # state (see the home.file comment in modules/home/ai/pi/default.nix), and
      # sessions/ holds compaction state. The eight spec categories therefore
      # reduce to five distinct probes, and rows sharing a probe cannot disagree
      # by construction.
      settingsFileDeclared = homeFileEnabled settingsTarget;
      sessionsTreeImmutable = hasImmutableHomeFileAtOrBelow sessionsTarget;
      runtimeStateCategories = [
        {
          name = "settings";
          immutable = settingsFileDeclared;
        }
        {
          name = "sessions";
          immutable = sessionsTreeImmutable;
        }
        {
          name = "compaction";
          immutable = sessionsTreeImmutable;
        }
        {
          name = "authentication";
          immutable = homeFileImmutable authenticationTarget;
        }
        {
          name = "project-trust";
          immutable = homeFileImmutable projectTrustTarget;
        }
        {
          name = "model-selection";
          immutable = settingsFileDeclared;
        }
        {
          name = "thinking-preferences";
          immutable = settingsFileDeclared;
        }
        {
          name = "extension-state";
          immutable = settingsFileDeclared || hasImmutableHomeFileAtOrBelow extensionStateTarget;
        }
      ];
      runtimeStateOutsideImmutableLinks = map (entry: entry.name) (
        builtins.filter (entry: !entry.immutable) runtimeStateCategories
      );
      activationScripts = map (entry: entry.data or "") (builtins.attrValues homeConfig.home.activation);
      canonicalSkillsScript = lib.findFirst (
        script: lib.hasInfix "/.agents/skills" script
      ) "" activationScripts;
      piSpecificSkillsPresent =
        lib.any (name: lib.hasInfix ".pi/agent/skills" name) (builtins.attrNames homeConfig.home.file)
        || lib.any (script: lib.hasInfix ".pi/agent/skills" script) activationScripts;
      contextTarget = "${piConfig.configDir}/AGENTS.md";
      globalInstructionsNixOwned =
        piConfig.context == homeConfig.programs.agents-md.settings.text && homeFileImmutable contextTarget;
      themeTarget = "${piConfig.configDir}/themes/catppuccin-mocha.json";
      themePath = "${toString ../home/ai/pi}/themes/catppuccin-mocha.json";
      themePresent = builtins.pathExists themePath;
      themeJson = if themePresent then builtins.fromJSON (builtins.readFile themePath) else { };
      immutableExtensionTargets = lib.optionals extensionSourceImmutable (
        map (selector: "pi-agent-extensions/${selector}") positiveExtensions
      );
      permissionRulesTarget = ".config/pi-agent-extensions/permission-gate/rules.ts";
      editWritePolicyTarget = "${piConfig.configDir}/extensions/edit-write-policy.ts";
      immutablePolicyTargets =
        lib.optional (
          extensionSourceImmutable && builtins.elem "permission-gate/index.ts" positiveExtensions
        ) "pi-agent-extensions/permission-gate/index.ts"
        ++ lib.optional (homeFileImmutable permissionRulesTarget) "~/.config/pi-agent-extensions/permission-gate/rules.ts"
        ++ lib.optional (homeFileImmutable editWritePolicyTarget) "~/.pi/agent/extensions/edit-write-policy.ts";
      permissionRulesPath = ../home/ai/pi/policy/permission-rules.ts;
      editWritePolicyPath = ../home/ai/pi/policy/edit-write-policy.ts;
      permissionRulesModule =
        if builtins.pathExists permissionRulesPath then
          permissionRulesPath
        else
          pkgs.writeText "missing-permission-rules.ts" ''
            export const policyPresent = false;
            export default function missingPermissionRules() { return {}; }
          '';
      editWritePolicyModule =
        if builtins.pathExists editWritePolicyPath then
          editWritePolicyPath
        else
          pkgs.writeText "missing-edit-write-policy.ts" ''
            export const policyPresent = false;
          '';
      # A shell case without `custom` runs against the built-in ruleset: the
      # harness passes `{}` in place of the deployed customConfig when `custom` is
      # falsy, so builtinShell and customShell exercise different engines.
      builtinShell = expected: name: command: {
        kind = "shell";
        inherit name command expected;
      };
      customShell =
        expected: name: command:
        (builtinShell expected name command) // { custom = true; };
      customShellBecause =
        expected: reason: name: command:
        (customShell expected name command) // { inherit reason; };
      shellCases = [
        # Baseline: a command matching no gated verb reaches the built-in engine
        # unchanged.
        (builtinShell "allow" "safe command is allowed" "printf '%s\\n' safe")
        # Read-only HTTP stays allowed. curl and wget default to GET, and none of
        # these spellings, long or negated or glued or short-clustered, sets a
        # request method or attaches a body.
        (customShell "allow" "safe curl GET is allowed" "curl --request GET https://example.invalid")
        (customShell "allow" "safe wget GET is allowed" "wget https://example.invalid/file")
        (customShell "allow" "safe curl HEAD is allowed" "curl --request HEAD https://example.invalid")
        (customShell "allow" "safe curl silent flag is allowed" "curl --silent https://example.invalid")
        (customShell "allow" "safe curl head flag is allowed" "curl --head https://example.invalid")
        (customShell "allow" "safe curl location flag is allowed" "curl --location https://example.invalid")
        (customShell "allow" "safe curl combined long flags are allowed"
          "curl --silent --show-error --location https://example.invalid"
        )
        (customShell "allow" "safe curl negated long flag is allowed"
          "curl --no-location https://example.invalid"
        )
        (customShell "allow" "safe curl combined silent short flags are allowed"
          "curl -sS https://example.invalid"
        )
        (customShell "allow" "safe curl combined head and location short flags are allowed"
          "curl -IL https://example.invalid"
        )
        (customShell "allow" "safe curl ordinary short flag cluster is allowed"
          "curl -fsSL https://example.invalid"
        )
        (customShell "allow" "safe wget OPTIONS is allowed" "wget --method OPTIONS https://example.invalid")
        # sudo is a built-in prompt rule, so this row must reach the built-in engine
        # to assert it.
        (builtinShell "prompt" "dangerous built-in sudo prompts" "sudo id")
        # rm is blocked wherever the pipeline can reach it: direct, composed, and
        # deferred through -exec.
        (customShellBecause "block" "rip" "direct rm blocks" "rm file.txt")
        (customShellBecause "block" "rip" "composed rm blocks" "printf done && rm -f file.txt")
        (customShellBecause "block" "rip" "deferred rm blocks" "find . -name '*.tmp' -exec rm {} +")
        # Worktree and workspace creation prompts. The rows below walk every route to
        # the subcommand, starting with the direct one.
        (customShell "prompt" "git worktree creation prompts" "git worktree add ../feature feature")
        (customShell "prompt" "jj workspace creation prompts" "jj workspace add ../feature")
        # A global option may not hide the subcommand, whether it is known, wrapped,
        # composed, or unrecognized.
        (customShell "prompt" "git global option before worktree prompts"
          "git -C /repo worktree add ../feature feature"
        )
        (customShell "prompt" "wrapped Git global option before worktree prompts"
          "env git --no-pager -C /repo worktree add ../feature feature"
        )
        (customShell "prompt" "composed jj global option before workspace prompts"
          "printf ready && jj -R /repo workspace add ../feature"
        )
        (customShell "prompt" "git short paginate alias before worktree prompts"
          "git -p worktree add ../feature feature"
        )
        (customShell "prompt" "wrapped Git short no-pager alias before worktree prompts"
          "env git -P worktree add ../feature feature"
        )
        (customShell "prompt" "composed jj debug flag before workspace prompts"
          "printf ready && jj --debug workspace add ../feature"
        )
        (customShell "prompt" "unknown Git global cannot hide worktree creation"
          "git --future-global value worktree add ../feature feature"
        )
        (customShell "prompt" "wrapped unknown jj global cannot hide workspace creation"
          "env jj --future-global value workspace add ../feature"
        )
        (customShell "prompt" "composed unknown Git global cannot hide worktree creation"
          "printf ready && git --future-global=value worktree add ../feature feature"
        )
        # A global option's value is a value, not a subcommand. jj still prompts here
        # because -R consumes `workspace`, leaving `add` in command position as an
        # alias the gate cannot resolve.
        (customShell "allow" "Git global option value is not a worktree subcommand"
          "git -C worktree add ../feature feature"
        )
        (customShell "prompt" "jj global option value followed by unresolved alias prompts"
          "jj -R workspace add ../feature"
        )
        # Aliases injected on the argv are parsed out of the -c/--config entries, so
        # quoting, embedded `add`, and the TOML spelling all resolve to the same
        # creation.
        (customShell "prompt" "argv-injected Git worktree alias prompts"
          "git -c alias.wt=worktree wt add ../feature feature"
        )
        (customShell "prompt" "wrapped argv-injected jj workspace alias prompts"
          "env jj --config 'aliases.ws=[\"workspace\"]' ws add ../feature"
        )
        (customShell "prompt" "Git injected alias overriding known command prompts"
          "git -c alias.remote=worktree remote add ../feature feature"
        )
        (customShell "prompt" "jj injected alias overriding known command prompts"
          "jj --config 'aliases.bookmark=[\"workspace\"]' bookmark add ../feature"
        )
        (customShell "prompt" "Git injected alias embedding worktree add prompts"
          "git -c 'alias.wa=worktree add' wa ../feature feature"
        )
        (customShell "prompt" "wrapped Git injected alias embedding worktree add prompts"
          "env git -c 'alias.wa=worktree add' wa ../feature feature"
        )
        (customShell "prompt" "jj injected alias embedding workspace add prompts"
          "jj --config 'aliases.wa=[\"workspace\",\"add\"]' wa ../feature"
        )
        (customShell "prompt" "wrapped jj injected alias embedding workspace add prompts"
          "env jj --config 'aliases.wa=[\"workspace\",\"add\"]' wa ../feature"
        )
        (customShell "prompt" "Git mixed-quoted embedded-add alias prompts"
          "git -c 'alias.wa=worktree \"add\"' wa ../feature feature"
        )
        (customShell "prompt" "wrapped jj literal-string embedded-add alias prompts"
          "env jj --config \"aliases.wa=['workspace','add']\" wa ../feature"
        )
        (customShell "prompt" "unparseable invoked injected alias prompts"
          "git -c 'alias.wa=!complex shell expansion' wa ../feature feature"
        )
        (customShell "prompt" "composed argv-injected jj TOML workspace alias prompts"
          "printf ready && jj --config-toml 'aliases.ws = [\"workspace\"]' ws add ../feature"
        )
        # A persistent alias is defined in config the gate cannot read, so an
        # unresolvable command in alias position prompts rather than being assumed
        # benign.
        (customShell "prompt" "persistent unknown Git alias-shaped add prompts"
          "git wt add ../feature feature"
        )
        (customShell "prompt" "persistent Git alias embedding worktree add prompts without literal add"
          "git wa ../feature feature"
        )
        (customShell "prompt" "wrapped persistent unknown jj alias-shaped add prompts"
          "env jj ws add ../feature"
        )
        (customShell "prompt" "persistent jj alias embedding workspace add prompts without literal add"
          "jj wa ../feature"
        )
        (customShell "prompt" "unknown Git global cannot hide persistent alias-shaped add"
          "git --future-global value wt add ../feature feature"
        )
        # Ordinary Git commands stay allowed.
        (customShell "allow" "known Git remote add remains allowed"
          "git remote add origin https://example.invalid/repo.git"
        )
        (customShell "allow" "ordinary Git status remains allowed" "git status --short")
        (customShell "allow" "ordinary Git grep remains allowed" "git grep needle")
        (customShell "allow" "ordinary Git blame remains allowed" "git blame -- file.ts")
        (customShell "allow" "ordinary Git rev-parse remains allowed" "git rev-parse HEAD")
        (customShell "allow" "ordinary Git ls-files remains allowed" "git ls-files")
        (customShell "allow" "ordinary Git archive remains allowed" "git archive --format=tar HEAD")
        (customShell "allow" "ordinary Git show-ref remains allowed" "git show-ref")
        # Git's informational globals short-circuit before any subcommand, so
        # mutation-shaped trailing argv is inert.
        (customShell "allow" "Git global version information remains allowed" "git --version")
        (customShell "allow" "Git global version ignores mutation-shaped trailing argv"
          "git --version worktree add ../feature feature"
        )
        (customShell "allow" "Git global help remains allowed" "git --help")
        (customShell "allow" "Git global help ignores worktree subcommand argv" "git --help worktree add")
        (customShell "allow" "Git global HTML path remains allowed" "git --html-path")
        (customShell "allow" "Git global man path remains allowed" "git --man-path")
        (customShell "allow" "Git global info path remains allowed" "git --info-path")
        (customShell "allow" "Git global exec path remains allowed" "git --exec-path")
        # The jj surface mirrors the Git one: ordinary commands and built-in aliases
        # allowed, informational globals short-circuiting, and anything the gate
        # cannot resolve prompting.
        (customShell "allow" "ordinary jj bookmark list remains allowed" "jj bookmark list")
        (customShell "allow" "ordinary jj log remains allowed" "jj log -r @")
        (customShell "allow" "jj help remains allowed" "jj help")
        (customShell "allow" "jj revert remains allowed" "jj revert -r @")
        (customShell "allow" "jj bisect remains allowed" "jj bisect run true")
        (customShell "allow" "jj sign remains allowed" "jj sign -r @")
        (customShell "allow" "jj operation alias remains allowed" "jj op log")
        (customShell "allow" "jj status alias remains allowed" "jj st")
        (customShell "allow" "jj long version remains allowed" "jj --version")
        (customShell "allow" "jj short version remains allowed" "jj -V")
        (customShell "allow" "jj long help remains allowed" "jj --help")
        (customShell "allow" "jj short help remains allowed" "jj -h")
        (customShell "allow" "jj subcommand help remains allowed" "jj help workspace")
        (customShell "allow" "jj informational version short-circuits workspace add"
          "jj --version workspace add ../feature"
        )
        (customShell "allow" "jj informational help short-circuits workspace add" "jj --help workspace add")
        (customShell "allow" "jj at-operation log remains allowed" "jj --at-op @ log -r @")
        (customShell "prompt" "jj at-operation workspace add still prompts"
          "jj --at-op @ workspace add ../feature"
        )
        (customShell "prompt" "unknown jj command prompts" "jj frobnicate")
        # Pi package state is pinned by Nix (modules/home/ai/pi/default.nix), so the
        # mutating pi subcommands are blocked while read-only ones stay allowed.
        (customShellBecause "block" "Nix" "pi install blocks" "pi install npm:example")
        (customShellBecause "block" "Nix" "pi remove blocks through wrapper" "env pi remove npm:example")
        (customShellBecause "block" "Nix" "pi uninstall blocks" "pi uninstall npm:example")
        (customShellBecause "block" "Nix" "pi update blocks" "pi update")
        (customShellBecause "block" "Nix" "pi config blocks" "pi config")
        (customShell "allow" "pi list remains allowed" "pi list")
        # curl request-method state. The argv is replayed as a state machine: the
        # last method-setting option wins, option values are never re-read as
        # options, and --next or -: opens a transfer that cannot retroactively
        # launder an earlier mutation.
        (customShell "prompt" "curl separate request mutation prompts"
          "curl --request POST https://example.invalid"
        )
        (customShell "prompt" "curl equals request mutation prompts"
          "curl --request=PATCH https://example.invalid"
        )
        (customShell "prompt" "curl glued request mutation prompts"
          "curl -XDELETE https://example.invalid/item"
        )
        (customShell "prompt" "curl glued data value containing XGET prompts"
          "curl -dXGET https://example.invalid/item"
        )
        (customShell "allow" "curl glued header value containing XGET is allowed"
          "curl -HXGET https://example.invalid/item"
        )
        (customShell "prompt" "curl valid short option cluster request mutation prompts"
          "curl -sXPOST https://example.invalid/item"
        )
        (customShell "prompt" "curl final request option controls mutation"
          "curl -XGET --request DELETE https://example.invalid/item"
        )
        (customShell "prompt" "curl next transfer cannot hide earlier mutation"
          "curl -XPOST https://example.invalid/first --next -XGET https://example.invalid/second"
        )
        (customShell "prompt" "curl short next alias cannot hide earlier mutation"
          "curl -XPOST https://example.invalid/first -: -XGET https://example.invalid/second"
        )
        (customShell "allow" "curl long next token consumed as header value is allowed"
          "curl -H --next https://example.invalid/resource"
        )
        (customShell "allow" "curl short next token consumed as header value is allowed"
          "curl -H -: https://example.invalid/resource"
        )
        (customShell "allow" "curl next tokens after end-of-options are positional" "curl -- --next -:")
        (customShell "allow" "curl safe long multi-transfer is allowed"
          "curl -XGET https://example.invalid/first --next -XHEAD https://example.invalid/second"
        )
        (customShell "allow" "curl safe short multi-transfer is allowed"
          "curl -XGET https://example.invalid/first -: -XHEAD https://example.invalid/second"
        )
        (customShell "prompt" "curl mutation after long boundary prompts"
          "curl -XGET https://example.invalid/first --next -XPOST https://example.invalid/second"
        )
        (customShell "prompt" "curl mutation after short boundary prompts"
          "curl -XGET https://example.invalid/first -: -XPOST https://example.invalid/second"
        )
        (customShell "prompt" "curl WebDAV MKCOL prompts"
          "curl --request MKCOL https://example.invalid/collection"
        )
        (customShell "prompt" "curl custom explicit method prompts"
          "curl -XFROB https://example.invalid/resource"
        )
        (customShell "prompt" "curl lowercase method is not read-only GET"
          "curl --request get https://example.invalid/resource"
        )
        # A method the gate cannot see is a mutation: an opaque config file, a body,
        # an upload, or an option the spec does not classify.
        (customShell "prompt" "curl long config prompts"
          "curl --config request.conf https://example.invalid"
        )
        (customShell "prompt" "curl glued short config prompts"
          "curl -Krequest.conf https://example.invalid"
        )
        (customShell "prompt" "curl data mutation prompts" "curl --data=value https://example.invalid")
        (customShell "prompt" "curl no-get after get restores data mutation"
          "curl --get --no-get --data payload URL"
        )
        (customShell "prompt" "curl no-get after short get restores upload mutation"
          "curl -G --no-get --upload-file payload URL"
        )
        (customShell "allow" "curl later get restores GET semantics"
          "curl --get --no-get --get --data payload URL"
        )
        (customShell "prompt" "curl expand-data mutation prompts"
          "curl --expand-data=payload https://example.invalid"
        )
        (customShell "prompt" "curl unclassified future long option prompts"
          "curl --future-option value https://example.invalid"
        )
        (customShell "prompt" "curl unclassified future short option prompts"
          "curl -W https://example.invalid"
        )
        (customShell "prompt" "curl upload mutation prompts" "curl -Tpayload https://example.invalid")
        (customShell "prompt" "curl read-only method cannot mask data mutation"
          "curl -XGET --data payload https://example.invalid/resource"
        )
        (customShell "prompt" "curl read-only method cannot mask upload mutation"
          "curl -XGET --upload-file payload https://example.invalid/resource"
        )
        (customShell "allow" "curl get conversion with read-only method remains allowed"
          "curl -G -XGET --data payload https://example.invalid/resource"
        )
        # wget replays the same state machine over its own spelling: --method,
        # --post-data and --body-data, --config, and --execute.
        (customShell "prompt" "wget separate method mutation prompts"
          "wget --method POST https://example.invalid"
        )
        (customShell "prompt" "wget equals method mutation prompts"
          "wget --method=DELETE https://example.invalid/item"
        )
        (customShell "prompt" "wget post data mutation prompts"
          "wget --post-data=payload https://example.invalid"
        )
        (customShell "prompt" "wget read-only method cannot mask body mutation"
          "wget --method=GET --body-data=payload https://example.invalid/resource"
        )
        (customShell "prompt" "wget WebDAV MOVE prompts"
          "wget --method MOVE https://example.invalid/resource"
        )
        (customShell "prompt" "wget custom explicit method prompts"
          "wget --method=FROB https://example.invalid/resource"
        )
        (customShell "prompt" "wget lowercase method is not read-only HEAD"
          "wget --method=head https://example.invalid/resource"
        )
        (customShell "prompt" "wget header value resembling method cannot mask post data"
          "wget --header --method=GET --post-data payload https://example.invalid/resource"
        )
        (customShell "prompt" "composed wget body value resembling safe method prompts"
          "printf ready && wget --post-data --method=GET https://example.invalid/resource"
        )
        (customShell "allow" "wget ordinary header value remains allowed"
          "wget --header 'Accept: application/json' https://example.invalid/resource"
        )
        (customShell "prompt" "wget opaque config prompts"
          "wget --config=request.conf https://example.invalid/resource"
        )
        (customShell "prompt" "wrapped wget short execute prompts"
          "env wget -euse_proxy=yes https://example.invalid/resource"
        )
        (customShell "prompt" "wget long execute prompts"
          "wget --execute=use_proxy=yes https://example.invalid/resource"
        )
        (customShell "prompt" "wget malformed method prompts" "wget --method")
        (customShell "prompt" "wget ambiguous unknown option prompts"
          "wget --future-option value https://example.invalid/resource"
        )
        # Without a UI there is nothing to prompt, so a prompt decision degrades to a
        # block.
        {
          kind = "shell";
          name = "headless HTTP prompt blocks";
          command = "curl -XPOST https://example.invalid";
          expected = "block";
          reason = "no UI";
          custom = true;
          headless = true;
        }
        # Pins gate discovery of rules.ts at the path home-manager installs it
        # to. The reason is a custom-rule phrase the built-in ruleset never
        # emits, so a broken discovery path allows here instead of blocking
        # rather than failing as a module resolution error.
        {
          kind = "shell";
          name = "gate discovers the deployed rules module";
          command = "rm file.txt";
          expected = "block";
          reason = "rip";
          custom = true;
          headless = true;
        }
        # A rule that throws is reported as a block carrying the diagnostic rather
        # than falling through to allow.
        {
          kind = "shell-error";
          name = "throwing parser rule blocks diagnostically";
          expected = "block";
          reason = "rule evaluation failed";
        }
      ];
      projectCases = [
        {
          kind = "project";
          name = "project cannot replace rules";
          project = {
            rules = [
              {
                label = "allow everything";
                pattern = ".*";
              }
            ];
          };
          command = "sudo id";
          expected = "prompt";
          warning = "may not replace rules";
        }
        {
          kind = "project";
          name = "project cannot disable block rules";
          project.disabledRules = [ "scan /nix/store" ];
          command = "rg needle /nix/store";
          expected = "block";
          warning = "may not disable block rule";
        }
        {
          kind = "project";
          name = "project cannot disable protected prompt rules";
          project.disabledRules = [ "modify gate config" ];
          command = "tee ~/.config/pi-agent-extensions/permission-gate/rules.ts < payload";
          expected = "prompt";
          warning = "may not disable load-bearing prompt rule";
        }
        {
          kind = "project";
          name = "project cannot disable headless prompt rules";
          project.disabledRules = [ "sudo" ];
          command = "sudo id";
          expected = "block";
          warning = "may not disable prompt rule(s) without a UI";
          headless = true;
        }
      ];
      coreCases = map (case: { kind = "core"; } // case) [
        {
          name = "path outside any repository blocks as unrecoverable";
          expected = "block";
          reason = "outside a recognized repository";
          input = {
            operation = "edit";
            target.canonicalPath = "/workspace/note.txt";
            repository.kind = "outside-repository";
          };
        }
        {
          name = "git feature branch allows";
          expected = "allow";
          input = {
            operation = "edit";
            target.canonicalPath = "/repo/file.ts";
            repository = {
              kind = "git";
              root = "/repo";
              head = {
                kind = "feature";
                branch = "feature/policy";
              };
            };
          };
        }
        {
          name = "git double-dot-prefixed child allows";
          expected = "allow";
          input = {
            operation = "edit";
            target.canonicalPath = "/repo/..config";
            repository = {
              kind = "git";
              root = "/repo";
              head = {
                kind = "feature";
                branch = "feature/policy";
              };
            };
          };
        }
        {
          name = "git target outside the repository root blocks";
          expected = "block";
          reason = "does not contain the canonical target";
          input = {
            operation = "write";
            target.canonicalPath = "/elsewhere/file.ts";
            repository = {
              kind = "git";
              root = "/repo";
              head = {
                kind = "feature";
                branch = "feature/policy";
              };
            };
          };
        }
        {
          name = "git main notifies and allows";
          expected = "notify";
          reason = "main";
          input = {
            operation = "write";
            target.canonicalPath = "/repo/file.ts";
            repository = {
              kind = "git";
              root = "/repo";
              head = {
                kind = "protected";
                branch = "main";
              };
            };
          };
        }
        {
          name = "git master notifies and allows";
          expected = "notify";
          reason = "master";
          input = {
            operation = "edit";
            target.canonicalPath = "/repo/file.ts";
            repository = {
              kind = "git";
              root = "/repo";
              head = {
                kind = "protected";
                branch = "master";
              };
            };
          };
        }
        {
          name = "indeterminate repository state allows";
          expected = "allow";
          input = {
            operation = "edit";
            target.canonicalPath = "/repo/file.ts";
            repository = {
              kind = "invalid";
              diagnostic = "ambiguous repository identity";
            };
          };
        }
      ];
      jjArgvOracle = {
        root = [
          "jj"
          "--ignore-working-copy"
          "root"
        ];
        current = [
          "jj"
          "--ignore-working-copy"
          "log"
          "-r"
          "@"
          "--no-graph"
          "-T"
          ''change_id ++ "\t" ++ commit_id ++ "\t" ++ conflict ++ "\t" ++ empty ++ "\t" ++ parents.len() ++ "\n"''
        ];
        currentIdentity = [
          "jj"
          "--ignore-working-copy"
          "log"
          "-r"
          "change-a"
          "--no-graph"
          "-T"
          ''commit_id ++ "\n"''
        ];
        defaultBookmarks = [
          "jj"
          "--ignore-working-copy"
          "bookmark"
          "list"
          "exact:main"
          "exact:master"
          "-T"
          ''if(!remote, added_targets.map(|c| name ++ "\t" ++ c.commit_id() ++ "\n").join(""))''
        ];
        classifyWip = [
          "jj"
          "--ignore-working-copy"
          "bookmark"
          "list"
          "exact:wip"
          "-T"
          ''if(!remote, name ++ "\t" ++ conflict ++ "\n")''
        ];
        resolveWip = [
          "jj"
          "--ignore-working-copy"
          "bookmark"
          "list"
          "exact:wip"
          "-T"
          ''if(!remote, added_targets.map(|c| c.commit_id() ++ "\t" ++ conflict ++ "\n").join(""))''
        ];
        join = [
          "jj"
          "--ignore-working-copy"
          "log"
          "-r"
          "@-"
          "--no-graph"
          "-T"
          ''commit_id ++ "\t" ++ conflict ++ "\t" ++ empty ++ "\t" ++ parents.len() ++ "\n"''
        ];
        parents = [
          "jj"
          "--ignore-working-copy"
          "log"
          "-r"
          "parents(@-)"
          "--no-graph"
          "-T"
          ''commit_id ++ "\t" ++ conflict ++ "\n"''
        ];
      };
      # The production inspector runs these eight read-only probes straight-line
      # with early returns (modules/home/ai/pi/policy/edit-write-policy.ts issues
      # JJ_READ_ARGV.root first, then current, currentIdentity, defaultBookmarks,
      # classifyWip, resolveWip, join, parents), so every scenario's recorded
      # argv sequence is a prefix of one total order and is characterized by the
      # last probe it reaches. A scenario whose probe order is not such a prefix
      # cannot be expressed as a depth here and needs an explicit literal.
      jjProbeSequence =
        let
          inherit (jjArgvOracle)
            classifyWip
            current
            currentIdentity
            defaultBookmarks
            join
            parents
            resolveWip
            root
            ;
        in
        [
          root
          current
          currentIdentity
          defaultBookmarks
          classifyWip
          resolveWip
          join
          parents
        ];
      # inspectJj in edit-write-policy.ts runs these eight read-only probes
      # straight-line with early returns, so every scenario's recorded argv
      # sequence is a prefix of one total order and is characterized by the count
      # of probes it reaches. A scenario whose probe order is not such a prefix
      # cannot be expressed here and needs an explicit expectedJjArgv literal.
      repositoryCaseTable = [
        {
          scenario = "ordinary-healthy";
          probes = 5;
          expected = "allow";
        }
        {
          scenario = "ordinary-nonempty-at";
          probes = 5;
          expected = "allow";
        }
        {
          scenario = "ordinary-conflict";
          probes = 5;
          expected = "notify";
        }
        {
          scenario = "ordinary-divergent-at";
          probes = 5;
          expected = "notify";
        }
        {
          scenario = "ordinary-main-at";
          probes = 5;
          expected = "notify";
        }
        {
          scenario = "ordinary-master-at";
          probes = 5;
          expected = "notify";
        }
        {
          scenario = "diamond-healthy";
          probes = 8;
          expected = "allow";
        }
        {
          scenario = "diamond-nonempty-wip";
          probes = 8;
          expected = "allow";
        }
        {
          scenario = "diamond-resolved-nonempty-join";
          probes = 8;
          expected = "allow";
        }
        # These four share an identical 8-probe argv, so only the reason phrase
        # separates absent from moved from divergent. The phrase is spelled in
        # full because the bare discriminant "divergent" is also emitted by the
        # unrelated current-change identity check.
        {
          scenario = "diamond-missing-wip";
          probes = 8;
          expected = "notify";
          reason = "wip bookmark is absent";
        }
        {
          scenario = "diamond-moved-wip";
          probes = 8;
          expected = "notify";
          reason = "wip bookmark is moved";
        }
        {
          scenario = "diamond-divergent-wip";
          probes = 8;
          expected = "notify";
          reason = "wip bookmark is divergent";
        }
        {
          scenario = "diamond-divergent-wip-without-target";
          probes = 8;
          expected = "notify";
          reason = "wip bookmark is divergent";
        }
        {
          scenario = "diamond-divergent-wip-malformed-resolution";
          probes = 6;
          expected = "allow";
        }
        {
          scenario = "diamond-nonsingle-parent-wip";
          probes = 8;
          expected = "notify";
        }
        {
          scenario = "diamond-single-parent-join";
          probes = 8;
          expected = "notify";
        }
        {
          scenario = "diamond-conflicted-join";
          probes = 8;
          expected = "notify";
        }
        {
          scenario = "diamond-conflicted-immediate-parent";
          probes = 8;
          expected = "notify";
        }
        {
          scenario = "diamond-join-parent-count-mismatch";
          probes = 8;
          expected = "allow";
        }
        {
          scenario = "diamond-malformed-join-probe";
          probes = 7;
          expected = "allow";
        }
        {
          scenario = "diamond-failing-join-probe";
          probes = 7;
          expected = "allow";
        }
        {
          scenario = "malformed-probe";
          probes = 2;
          expected = "allow";
        }
        {
          scenario = "malformed-parent-count-probe";
          probes = 2;
          expected = "allow";
        }
        {
          scenario = "failing-probe";
          probes = 2;
          expected = "allow";
        }
        {
          scenario = "ambiguous-probe";
          probes = 2;
          expected = "allow";
        }
        {
          scenario = "failing-root-probe";
          probes = 1;
          expected = "allow";
        }
        {
          scenario = "outside-jj-contradictory-stdout";
          probes = 1;
          expected = "allow";
        }
        {
          scenario = "outside-jj-wrong-status";
          probes = 1;
          expected = "allow";
        }
        {
          scenario = "outside-jj-mixed-diagnostics";
          probes = 1;
          expected = "block";
          reason = "outside a recognized repository";
        }
        {
          # Regression oracle for the anchored jj diagnostic. jujutsu 0.43.0
          # appends the Hint lines below whenever the probed directory holds a
          # .git directory, which is exactly the case that has to reach the Git
          # branch. While the match was anchored at the end of stderr this row
          # blocked with "jj root", so the Git arm was unreachable at the root
          # of every ordinary Git repository.
          scenario = "outside-jj-hint-git-main";
          probes = 1;
          expected = "notify";
          reason = "main";
        }
        {
          scenario = "classification-whitespace-only";
          probes = 5;
          expected = "allow";
        }
        {
          scenario = "classification-padded";
          probes = 5;
          expected = "allow";
        }
        {
          scenario = "classification-extra-blank";
          probes = 5;
          expected = "allow";
        }
        {
          scenario = "root-padded";
          probes = 1;
          expected = "allow";
        }
        {
          scenario = "current-extra-blank";
          probes = 2;
          expected = "allow";
        }
        {
          scenario = "identity-padded";
          probes = 3;
          expected = "allow";
        }
        {
          scenario = "defaults-extra-blank";
          probes = 4;
          expected = "allow";
        }
        {
          scenario = "resolution-padded";
          probes = 6;
          expected = "allow";
        }
        {
          scenario = "parents-extra-blank";
          probes = 8;
          expected = "allow";
        }
        {
          scenario = "canonical-root-mismatch";
          probes = 1;
          expected = "allow";
        }
        {
          scenario = "target-jj-cwd-other-repository";
          probes = 5;
          expected = "allow";
          target = "/target/new/file.ts";
          cwd = "/cwd";
          expectedProbeCwd = "/target";
        }
        {
          scenario = "target-git-cwd-jj-repository";
          probes = 1;
          expected = "allow";
          target = "/target/new/file.ts";
          cwd = "/cwd";
          expectedProbeCwd = "/target";
          expectedGitRootDirectory = "/target";
          expectedGitHeadDirectory = "/target";
        }
        {
          scenario = "git-protected-head";
          probes = 1;
          expected = "notify";
          reason = "main";
        }
        {
          scenario = "git-feature-head";
          probes = 1;
          expected = "allow";
        }
        {
          scenario = "git-detached-head";
          probes = 1;
          expected = "allow";
        }
        {
          scenario = "git-malformed-head";
          probes = 1;
          expected = "allow";
        }
        {
          scenario = "git-multiline-head";
          probes = 1;
          expected = "allow";
        }
        {
          scenario = "colocated-healthy";
          probes = 5;
          expected = "allow";
          expectedGitRootDirectory = "/repo";
        }
        {
          scenario = "colocated-divergent-roots";
          probes = 1;
          expected = "allow";
          expectedGitRootDirectory = "/repo";
        }
      ];
      repositoryCases = map (
        row:
        builtins.removeAttrs row [ "probes" ]
        // {
          kind = "repository";
          name = "repository ${row.scenario}";
          expectedJjArgv = if row ? probes then lib.take row.probes jjProbeSequence else null;
        }
      ) repositoryCaseTable;
      gitRootCases = map (case: { kind = "git-root"; } // case) [
        {
          name = "characterized Git outside result is accepted";
          result = {
            stdout = "";
            stderr = "fatal: not a git repository (or any of the parent directories): .git\n";
            code = 128;
          };
          expected = "outside";
        }
        {
          name = "Git outside result with contradictory stdout is invalid";
          result = {
            stdout = "/repo\n";
            stderr = "fatal: not a git repository (or any of the parent directories): .git\n";
            code = 128;
          };
          expected = "invalid";
          reason = "Git root";
        }
        {
          name = "Git outside result with wrong status is invalid";
          result = {
            stdout = "";
            stderr = "fatal: not a git repository (or any of the parent directories): .git\n";
            code = 1;
          };
          expected = "invalid";
          reason = "Git root";
        }
        {
          # Prefix match: Git appends advice after the diagnostic in some
          # configurations, and treating that as unparseable is what made the
          # jj analogue swallow every write at a repository root.
          name = "Git outside result with trailing diagnostics is accepted";
          result = {
            stdout = "";
            stderr = "fatal: not a git repository (or any of the parent directories): .git\nadditional diagnostic\n";
            code = 128;
          };
          expected = "outside";
        }
      ];
      adapterCases = map (case: { kind = "adapter"; } // case) [
        {
          name = "adapter registers only tool_call handler";
          scenario = "registration";
          expected = "pass";
        }
        {
          name = "adapter translates edit allow";
          scenario = "git-feature";
          tool = "edit";
          input.path = "/repo/file.ts";
          expected = "pass";
        }
        {
          name = "adapter translates write allow";
          scenario = "git-feature";
          tool = "write";
          input.path = "/repo/file.ts";
          expected = "pass";
        }
        {
          name = "adapter permits a notify decision and announces it";
          scenario = "git-main";
          tool = "write";
          input.path = "/repo/file.ts";
          expected = "pass";
          expectedNotification = "main";
        }
        {
          name = "adapter blocks a target outside any repository";
          scenario = "outside-repository";
          tool = "edit";
          input.path = "/workspace/file.ts";
          expected = "block";
          reason = "outside a recognized repository";
        }
        {
          # Without the @ strip this resolves under cwd and lands inside the
          # repository, so the row discriminates the normalization rather than
          # merely exercising it.
          name = "adapter strips a Pi at-prefix before resolving";
          scenario = "outside-repository";
          tool = "write";
          input.path = "@/workspace/file.ts";
          expected = "block";
          reason = "outside a recognized repository";
        }
        {
          # Likewise: unexpanded, "~/secret" resolves to <cwd>/~/secret, which
          # is inside the repository and would have been permitted.
          name = "adapter expands a leading tilde before resolving";
          scenario = "outside-repository";
          tool = "write";
          input.path = "~/secret";
          expected = "block";
          reason = "outside a recognized repository";
        }
        {
          name = "adapter passes unrelated tools through";
          scenario = "capability-throws";
          tool = "read";
          input.path = "/repo/file.ts";
          expected = "pass";
        }
        {
          name = "adapter blocks a non-string path";
          scenario = "git-feature";
          tool = "edit";
          input.path = 42;
          expected = "block";
          reason = "malformed";
        }
        {
          name = "adapter blocks an empty path";
          scenario = "git-feature";
          tool = "write";
          input.path = "";
          expected = "block";
          reason = "malformed";
        }
        {
          name = "adapter blocks a whitespace-only path";
          scenario = "git-feature";
          tool = "write";
          input.path = "   ";
          expected = "block";
          reason = "malformed";
        }
        {
          name = "adapter blocks a missing path key";
          scenario = "git-feature";
          tool = "edit";
          input = { };
          expected = "block";
          reason = "malformed";
        }
        {
          # atomic's edit tool takes a single hashline string under
          # additionalProperties: false, so no path can ever reach this adapter
          # from that agent and every atomic edit was refused as malformed.
          # This row records why the extension is scoped to Pi in
          # modules/home/ai/agent-settings.nix rather than taught a second tool
          # grammar; it is the shape the policy must never be asked to judge.
          name = "adapter cannot read atomic hashline edit input";
          scenario = "git-feature";
          tool = "edit";
          input.input = "[greeter.ts#A18E]\nreplace 1..1:\n+const x = 2;\n";
          expected = "block";
          reason = "malformed";
        }
        {
          name = "adapter permits core exceptions";
          scenario = "core-throws";
          tool = "edit";
          input.path = "/repo/file.ts";
          expected = "pass";
        }
        {
          name = "adapter permits capability exceptions";
          scenario = "capability-throws";
          tool = "write";
          input.path = "/repo/file.ts";
          expected = "pass";
        }
        {
          name = "adapter permits a missing filesystem capability";
          scenario = "capability-missing";
          tool = "edit";
          input.path = "/repo/file.ts";
          expected = "pass";
        }
        {
          name = "adapter permits a throwing capability factory";
          scenario = "capability-factory-throws";
          tool = "write";
          input.path = "/repo/file.ts";
          expected = "pass";
        }
        {
          name = "adapter permits a throwing notification capability";
          scenario = "notification-throws";
          tool = "write";
          input.path = "/repo/file.ts";
          expected = "pass";
        }
      ];
      normalizeCases = map (case: { kind = "normalize"; } // case) [
        {
          name = "normalize keeps an ordinary relative path";
          input = "src/a.ts";
          expected = "src/a.ts";
        }
        {
          name = "normalize strips a Pi at-prefix";
          input = "@/nix/store/x/f";
          expected = "/nix/store/x/f";
        }
        {
          name = "normalize expands a bare tilde";
          input = "~";
          expected = "/home/tester";
        }
        {
          name = "normalize expands a tilde path";
          input = "~/secret";
          expected = "/home/tester/secret";
        }
        {
          name = "normalize expands a tilde path behind an at-prefix";
          input = "@~/secret";
          expected = "/home/tester/secret";
        }
        {
          name = "normalize converts a file URL";
          input = "file:///etc/hosts";
          expected = "/etc/hosts";
        }
        {
          name = "normalize folds unicode space variants";
          input = builtins.fromJSON ''"a\u00a0b.txt"'';
          expected = "a b.txt";
        }
        {
          name = "normalize rejects a whitespace-only path";
          input = "   ";
          expected = "(undefined)";
        }
        {
          name = "normalize rejects a bare at-prefix";
          input = "@";
          expected = "(undefined)";
        }
      ];
      classificationCases = map (case: { kind = "classification"; } // case) [
        {
          name = "classification reports a malformed current probe";
          scenario = "malformed-probe";
          expected = "invalid";
          reason = "jj current probe is malformed";
        }
        {
          name = "classification reports a failing current probe";
          scenario = "failing-probe";
          expected = "invalid";
          reason = "jj current probe failed";
        }
        {
          name = "classification reports an ambiguous current probe";
          scenario = "ambiguous-probe";
          expected = "invalid";
          reason = "jj current probe is ambiguous";
        }
        {
          name = "classification reports a failing root probe";
          scenario = "failing-root-probe";
          expected = "invalid";
          reason = "jj root probe failed";
        }
        {
          name = "classification reports a malformed join probe";
          scenario = "diamond-malformed-join-probe";
          expected = "invalid";
          reason = "join probe is malformed";
        }
        {
          name = "classification reports a canonical root mismatch";
          scenario = "canonical-root-mismatch";
          expected = "invalid";
          reason = "does not contain the canonical target";
        }
        {
          name = "classification reports ambiguous Git and jj identities";
          scenario = "colocated-divergent-roots";
          expected = "invalid";
          reason = "ambiguous Git and jj repository identities";
        }
        {
          name = "classification reports a healthy diamond";
          scenario = "diamond-healthy";
          expected = "jj-diamond";
        }
        {
          name = "classification reports an ordinary jj repository";
          scenario = "ordinary-healthy";
          expected = "jj-ordinary";
        }
      ];
      policyCases = pkgs.writeText "pi-agent-environment-policy-cases.json" (
        builtins.toJSON (
          shellCases
          ++ projectCases
          ++ coreCases
          ++ repositoryCases
          ++ gitRootCases
          ++ adapterCases
          ++ normalizeCases
          ++ classificationCases
        )
      );
      # Ambient stand-ins for the only two type surfaces this sandbox cannot
      # resolve: pkgs/by-name/pi-agent-extensions/package.nix fails the build on
      # any node_modules, so there is no @types/node and no
      # @earendil-works/pi-coding-agent package to import from. Each block is
      # narrowed to the members imported at the top of
      # modules/home/ai/pi/policy/edit-write-policy.ts and is unverified against
      # upstream, so tsc proves internal consistency rather than host acceptance;
      # that file's default export signature is the only line whose host contract
      # rests on these. permission-rules.ts is unaffected — its sole import
      # resolves through the tsconfig path alias to the real pinned
      # permission-gate/types.ts.
      policyTypeDeclarations = pkgs.writeText "pi-agent-environment-policy-external.d.ts" ''
        declare namespace NodeJS {
          interface ErrnoException extends Error { code?: string | number }
        }
        declare module "node:child_process" {
          export function execFile(
            file: string,
            args: readonly string[],
            options: { cwd: string; encoding: "utf8" },
            callback: (error: NodeJS.ErrnoException | null, stdout: string, stderr: string) => void,
          ): void;
        }
        declare module "node:fs/promises" {
          interface Stats {
            isDirectory(): boolean;
          }
          export function realpath(path: string): Promise<string>;
          export function stat(path: string): Promise<Stats>;
        }
        declare module "node:path" {
          export function basename(path: string): string;
          export function dirname(path: string): string;
          export function isAbsolute(path: string): boolean;
          export function join(...paths: string[]): string;
          export function relative(from: string, to: string): string;
          export function resolve(...paths: string[]): string;
          export const sep: string;
        }
        declare module "node:fs" {
          export function copyFileSync(source: string, destination: string): void;
          export function mkdirSync(path: string, options?: { recursive?: boolean }): void;
          export function mkdtempSync(prefix: string): string;
          export function readFileSync(path: string, encoding: "utf8"): string;
          export function rmSync(path: string, options?: { recursive?: boolean; force?: boolean }): void;
          export function writeFileSync(path: string, data: string): void;
        }
        declare module "node:os" {
          export function homedir(): string;
          export function tmpdir(): string;
        }
        declare module "node:url" {
          export function fileURLToPath(url: string): string;
          export function pathToFileURL(path: string): { href: string };
        }
        declare module "bun:test" {
          export const mock: { module(specifier: string, factory: () => unknown): void };
        }
        declare const process: {
          env: Record<string, string> & {
            XDG_CONFIG_HOME?: string;
            PI_NO_GATE?: string;
          };
          exit(code: number): never;
        };
        declare module "@earendil-works/pi-coding-agent" {
          interface ToolCallEvent {
            readonly toolName: string;
            readonly toolCallId: string;
            readonly input: unknown;
          }
          interface ExtensionContext {
            readonly cwd: string;
            readonly hasUI: boolean;
            readonly ui: {
              notify(message: string, type?: "info" | "warning" | "error"): void;
            };
          }
          export interface ExtensionAPI {
            on(
              event: "tool_call",
              handler: (
                event: ToolCallEvent,
                context: ExtensionContext,
              ) => Promise<{ readonly block: true; readonly reason: string } | undefined>,
            ): void;
          }
        }
      '';
      # Residual limit: the harness reads its case table as JSON.parse output, so
      # every entry.<field> access is `any`. tsc validates the harness's own
      # helpers, locals and signatures, never a field access against the six case
      # shapes the Nix tables emit.
      policyTsconfig = pkgs.writeText "pi-agent-environment-policy-tsconfig.json" (
        builtins.toJSON {
          compilerOptions = {
            strict = true;
            noEmit = true;
            allowImportingTsExtensions = true;
            module = "ESNext";
            moduleResolution = "Bundler";
            target = "ES2022";
            paths."pi-agent-extensions/permission-gate/*" = [ "./permission-gate/*" ];
            skipLibCheck = true;
          };
          files = [
            "./external.d.ts"
            "./permission-rules.ts"
            "./edit-write-policy.ts"
            "./policy-test.ts"
          ];
        }
      );
      policyHarness = pkgs.writeText "pi-agent-environment-policy-test.ts" ''
        import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
        import { tmpdir } from "node:os";
        import { join } from "node:path";
        import { pathToFileURL } from "node:url";
        import { mock } from "bun:test";

        // pi injects @mariozechner/* as jiti virtual modules rather than
        // resolving them from node_modules (docs/notes/development/ai-agents/
        // pi-integration-reconnaissance.md:103), and the extension package
        // rejects any node_modules, so under bun these specifiers resolve to
        // nothing. permission-gate/index.ts value-imports ./ui.ts, which
        // value-imports exactly these five bindings; widen the mock if a loaded
        // gate module gains another pi-tui value import. Type-only imports are
        // erased and need no entry. This call must stay above the gate() imports
        // below, which load the module graph it patches.
        mock.module("@mariozechner/pi-tui", () => ({
          Editor: class {},
          Key: {},
          matchesKey: () => false,
          truncateToWidth: (value: string) => value,
          wrapTextWithAnsi: (value: string) => [value],
        }));

        const gateRoot = process.env.PERMISSION_GATE_ROOT;
        const gate = async (file: string) => import(pathToFileURL(gateRoot + "/" + file).href);
        const config = await gate("config.ts");
        const matcher = await gate("match.ts");
        const shell = await gate("shell.ts");
        const helpersModule = await gate("helpers.ts");
        const builtinsModule = await gate("builtin-rules.ts");
        const gateIndex = await gate("index.ts");
        const permissionModule = await import(pathToFileURL(process.env.PERMISSION_RULES_MODULE).href);
        const editModule = await import(pathToFileURL(process.env.EDIT_WRITE_POLICY_MODULE).href);
        const cases = JSON.parse(readFileSync(process.env.POLICY_CASES, "utf8"));
        const failures: string[] = [];

        const helpers = {
          simpleCommands: shell.simpleCommands,
          pipelines: shell.pipelines,
          searchPaths: builtinsModule.searchPaths,
          unwrap: shell.unwrap,
          unwrapSteps: shell.unwrapSteps,
          nestedScripts: shell.nestedScripts,
          deferredScripts: shell.deferredScripts,
          anyCmd: helpersModule.anyCmd,
          hasFlag: helpersModule.hasFlag,
          SHELLS: shell.SHELLS,
        };
        const hasPermissionPolicy = permissionModule.policyPresent === true && typeof permissionModule.default === "function";
        const hasEditPolicy = editModule.policyPresent === true && typeof editModule.decideEditWrite === "function";
        const editPolicyKinds = new Set(["git-root", "core", "repository", "adapter", "normalize", "classification"]);
        const customConfig = hasPermissionPolicy ? permissionModule.default(helpers) : {};

        function classify(command: string, userCode: unknown, project: unknown) {
          const warnings: string[] = [];
          try {
            const rules = config.compileRules(
              {
                userCode,
                userJson: {},
                project: config.sanitizeConfig(project, ".pi/permission-gate.json", false, (warning: string) => warnings.push(warning)),
              },
              (warning: string) => warnings.push(warning),
            );
            const matched = matcher.matchRules(command, rules);
            const blocked = matched.find((rule: { action: string }) => rule.action === "block");
            if (blocked) return { decision: "block", reason: blocked.reason ?? "Blocked", warnings };
            const prompted = matched.find((rule: { action: string }) => rule.action === "prompt");
            if (!prompted) return { decision: "allow", reason: "", warnings };
            return { decision: "prompt", reason: "", warnings };
          } catch (error) {
            return { decision: "block", reason: "rule evaluation failed: " + String(error), warnings };
          }
        }

        async function runGateHandler(options: {
          rulesSource?: string;
          rulesInline?: string;
          projectConfig?: unknown;
          command: string;
          hasUI: boolean;
        }) {
          const configRoot = mkdtempSync(join(tmpdir(), "permission-gate-handler-"));
          const rulesDirectory = join(configRoot, "pi-agent-extensions", "permission-gate");
          mkdirSync(rulesDirectory, { recursive: true });
          if (options.rulesInline !== undefined) {
            writeFileSync(join(rulesDirectory, "rules.mjs"), options.rulesInline);
          } else if (options.rulesSource !== undefined) {
            copyFileSync(options.rulesSource, join(rulesDirectory, "rules.ts"));
          }
          if (options.projectConfig !== undefined) {
            mkdirSync(join(configRoot, ".pi"), { recursive: true });
            writeFileSync(
              join(configRoot, ".pi", "permission-gate.json"),
              JSON.stringify(options.projectConfig),
            );
          }
          const previousConfigHome = process.env.XDG_CONFIG_HOME;
          const previousNoGate = process.env.PI_NO_GATE;
          const previousError = console.error;
          const warnings: string[] = [];
          process.env.XDG_CONFIG_HOME = configRoot;
          delete process.env.PI_NO_GATE;
          console.error = (message: unknown) => {
            warnings.push(String(message));
          };
          try {
            const handlers = new Map<string, Array<(event: unknown, context: unknown) => unknown>>();
            const pi = {
              on: (name: string, handler: (event: unknown, context: unknown) => unknown) => {
                const registered = handlers.get(name) ?? [];
                registered.push(handler);
                handlers.set(name, registered);
              },
              registerCommand: () => {},
              events: { on: () => () => {}, emit: () => {} },
            };
            gateIndex.default(pi);
            const context = { hasUI: options.hasUI, cwd: configRoot };
            for (const handler of handlers.get("session_start") ?? []) {
              await handler({}, context);
            }
            let result: { block?: boolean; reason?: string } | undefined;
            for (const handler of handlers.get("tool_call") ?? []) {
              result = await handler(
                { toolName: "bash", input: { command: options.command } },
                context,
              ) as { block?: boolean; reason?: string } | undefined;
            }
            return {
              decision: result?.block === true ? "block" : "allow",
              reason: result?.reason ?? "",
              warnings,
            };
          } finally {
            console.error = previousError;
            if (previousConfigHome === undefined) delete process.env.XDG_CONFIG_HOME;
            else process.env.XDG_CONFIG_HOME = previousConfigHome;
            if (previousNoGate === undefined) delete process.env.PI_NO_GATE;
            else process.env.PI_NO_GATE = previousNoGate;
            rmSync(configRoot, { recursive: true, force: true });
          }
        }

        function processResult(stdout = "", code = 0, stderr = "") {
          return { stdout, stderr, code };
        }

        type Probe = ReturnType<typeof processResult>;

        const jjCurrent = "change-a\tcommit-a\tfalse\ttrue\t2\n";
        const diamondCurrent = "change-a\tcommit-a\tfalse\ttrue\t1\n";
        const diamondJoin = "commit-join\tfalse\ttrue\t6\n";
        const diamondParents = Array.from(
          { length: 6 },
          (_, index) => `parent-''${index + 1}\tfalse\n`,
        ).join("");
        const ordinary = [
          processResult("/repo\n"),
          processResult(jjCurrent),
          processResult("commit-a\n"),
          processResult(""),
          processResult(""),
        ];
        const jjOutside = processResult("", 1, 'Error: There is no jj repo in "."\n');

        type DiamondSlots = {
          currentProbe: string;
          classification: Probe;
          resolution: Probe;
          joinProbe: Probe;
          parents: Probe;
        };

        function diamondFixture(mutate?: (slots: DiamondSlots) => void): Probe[] {
          const slots: DiamondSlots = {
            currentProbe: diamondCurrent,
            classification: processResult("wip\tfalse\n"),
            resolution: processResult("commit-a\tfalse\n"),
            joinProbe: processResult(diamondJoin),
            parents: processResult(diamondParents),
          };
          mutate?.(slots);
          return [
            ordinary[0],
            processResult(slots.currentProbe),
            ordinary[2],
            ordinary[3],
            slots.classification,
            slots.resolution,
            slots.joinProbe,
            slots.parents,
          ];
        }

        const jjFixtures: Record<string, () => Probe[]> = {
          "ordinary-healthy": () => ordinary,
          "ordinary-nonempty-at": () => [ordinary[0], processResult("change-a\tcommit-a\tfalse\tfalse\t1\n"), ...ordinary.slice(2)],
          "target-jj-cwd-other-repository": () => [processResult("/target\n"), ...ordinary.slice(1)],
          "ordinary-conflict": () => [ordinary[0], processResult("change-a\tcommit-a\ttrue\tfalse\t1\n"), ...ordinary.slice(2)],
          "ordinary-divergent-at": () => [ordinary[0], ordinary[1], processResult("commit-a\ncommit-b\n"), ...ordinary.slice(3)],
          "ordinary-main-at": () => [ordinary[0], ordinary[1], ordinary[2], processResult("main\tcommit-a\n"), ordinary[4]],
          "ordinary-master-at": () => [ordinary[0], ordinary[1], ordinary[2], processResult("master\tcommit-a\n"), ordinary[4]],
          "classification-whitespace-only": () => [...ordinary.slice(0, 4), processResult(" \n")],
          "classification-padded": () => [...ordinary.slice(0, 4), processResult(" wip\tfalse\n")],
          "classification-extra-blank": () => [...ordinary.slice(0, 4), processResult("wip\tfalse\n\n")],
          "root-padded": () => [processResult(" /repo\n"), ...ordinary.slice(1)],
          "current-extra-blank": () => [ordinary[0], processResult(jjCurrent + "\n"), ...ordinary.slice(2)],
          "identity-padded": () => [ordinary[0], ordinary[1], processResult(" commit-a\n"), ...ordinary.slice(3)],
          "defaults-extra-blank": () => [ordinary[0], ordinary[1], ordinary[2], processResult("\n"), ordinary[4]],
          "resolution-padded": () => [...ordinary.slice(0, 4), processResult("wip\tfalse\n"), processResult(" commit-a\tfalse\n"), processResult("parent-a\tfalse\nparent-b\tfalse\n")],
          "parents-extra-blank": () => [...ordinary.slice(0, 4), processResult("wip\tfalse\n"), processResult("commit-a\tfalse\n"), processResult(diamondJoin), processResult(diamondParents + "\n")],
          "malformed-probe": () => [ordinary[0], processResult("not-a-record\n")],
          "malformed-parent-count-probe": () => [ordinary[0], processResult("change-a\tcommit-a\tfalse\ttrue\t2x\n"), ...ordinary.slice(2)],
          "failing-probe": () => [ordinary[0], processResult("", 2, "probe failed")],
          "ambiguous-probe": () => [ordinary[0], processResult(jjCurrent + "change-b\tcommit-b\tfalse\tfalse\t1\n")],
          "failing-root-probe": () => [processResult("", 1, "permission denied")],
          "outside-jj-contradictory-stdout": () => [processResult("/repo\n", 1, jjOutside.stderr)],
          "outside-jj-wrong-status": () => [processResult("", 2, jjOutside.stderr)],
          "outside-jj-mixed-diagnostics": () => [processResult("", 1, jjOutside.stderr + "Hint: additional diagnostic\n")],
          "canonical-root-mismatch": () => [processResult("/other\n")],
          "diamond-healthy": () => diamondFixture(),
          "diamond-nonempty-wip": () => diamondFixture((slots) => {
            slots.currentProbe = "change-a\tcommit-a\tfalse\tfalse\t1\n";
          }),
          "diamond-resolved-nonempty-join": () => diamondFixture((slots) => {
            slots.joinProbe = processResult("commit-join\tfalse\tfalse\t6\n");
          }),
          "diamond-missing-wip": () => diamondFixture((slots) => {
            slots.resolution = processResult("");
          }),
          "diamond-moved-wip": () => diamondFixture((slots) => {
            slots.resolution = processResult("commit-other\tfalse\n");
          }),
          "diamond-divergent-wip": () => diamondFixture((slots) => {
            slots.classification = processResult("wip\ttrue\n");
            slots.resolution = processResult("commit-a\ttrue\ncommit-b\ttrue\n");
          }),
          "diamond-divergent-wip-without-target": () => diamondFixture((slots) => {
            slots.classification = processResult("wip\ttrue\n");
            slots.resolution = processResult("");
          }),
          "diamond-divergent-wip-malformed-resolution": () => diamondFixture((slots) => {
            slots.classification = processResult("wip\ttrue\n");
            slots.resolution = processResult("malformed-resolution\n");
          }),
          "diamond-nonsingle-parent-wip": () => diamondFixture((slots) => {
            slots.currentProbe = "change-a\tcommit-a\tfalse\ttrue\t2\n";
          }),
          "diamond-single-parent-join": () => diamondFixture((slots) => {
            slots.joinProbe = processResult("commit-join\tfalse\ttrue\t1\n");
            slots.parents = processResult("parent-1\tfalse\n");
          }),
          "diamond-conflicted-join": () => diamondFixture((slots) => {
            slots.joinProbe = processResult("commit-join\ttrue\tfalse\t6\n");
          }),
          "diamond-conflicted-immediate-parent": () => diamondFixture((slots) => {
            slots.parents = processResult(diamondParents.replace("parent-6\tfalse", "parent-6\ttrue"));
          }),
          "diamond-join-parent-count-mismatch": () => diamondFixture((slots) => {
            slots.parents = processResult(diamondParents.replace("parent-6\tfalse\n", ""));
          }),
          "diamond-malformed-join-probe": () => diamondFixture((slots) => {
            slots.joinProbe = processResult("not-a-join-record\n");
          }),
          "diamond-failing-join-probe": () => diamondFixture((slots) => {
            slots.joinProbe = processResult("", 2, "join probe failed");
          }),
          "outside-jj-hint-git-main": () => [
            processResult(
              "",
              1,
              jjOutside.stderr +
                "Hint: It looks like this is a git repo. You can create a jj repo backed by it by running this:\n" +
                "jj git init\n",
            ),
          ],
          "target-git-cwd-jj-repository": () => diamondFixture(),
          "colocated-healthy": () => ordinary,
          "colocated-divergent-roots": () => [ordinary[0]],
          "core-throws": () => diamondFixture(),
          "capability-missing": () => diamondFixture(),
          "capability-factory-throws": () => diamondFixture(),
        };

        const withoutJjScenarios = ["outside-repository", "capability-throws", "notification-throws"];
        const withoutJjFixture = (scenario: string) => withoutJjScenarios.includes(scenario) || scenario.startsWith("git-");

        function jjOutputs(scenario: string) {
          const build = jjFixtures[scenario];
          if (build === undefined) throw new Error("unknown jj scenario fixture: " + scenario);
          return build();
        }

        const fixtureConsumers = new Set(
          cases
            .filter((entry: { kind: string }) => entry.kind === "repository" || entry.kind === "adapter" || entry.kind === "classification")
            .map((entry: { scenario: string }) => entry.scenario)
            .filter((scenario: string) => scenario !== "registration" && !withoutJjFixture(scenario)),
        );
        for (const scenario of fixtureConsumers) {
          if (jjFixtures[scenario as string] === undefined) {
            failures.push("scenario declared in Nix has no TypeScript fixture: " + scenario);
          }
        }
        for (const scenario of Object.keys(jjFixtures)) {
          if (!fixtureConsumers.has(scenario)) {
            failures.push("TypeScript fixture is unused by any Nix case: " + scenario);
          }
        }

        function fakeCapabilities(
          scenario: string,
          calls: string[][],
          jjCwds: string[],
          gitRootDirectories: string[] = [],
          gitHeadDirectories: string[] = [],
          notifications: string[] = [],
        ) {
          const gitScenario =
              scenario.startsWith("git-") ||
              scenario === "target-git-cwd-jj-repository" ||
              scenario === "outside-jj-hint-git-main" ||
              scenario === "notification-throws";
          const outputs = withoutJjFixture(scenario) ? [jjOutside] : jjOutputs(scenario);
          let jjIndex = 0;
          return {
            filesystem: {
              homeDirectory: () => "/home/tester",
              canonicalize: async (target: string) => {
                if (scenario === "capability-throws") throw new Error("filesystem unavailable");
                return target;
              },
              inspectionDirectory: async (target: string) => {
                if (target.startsWith("/target/")) return "/target";
                if (target.startsWith("/workspace/")) return "/workspace";
                if (target.startsWith("/home/")) return "/home/tester";
                return "/repo";
              },
            },
            git: {
              root: async (directory: string) => {
                gitRootDirectories.push(directory);
                if (scenario === "colocated-healthy") return { kind: "inside", root: "/repo" };
                if (scenario === "colocated-divergent-roots") {
                  return { kind: "inside", root: "/repo/.claude/worktrees/linked" };
                }
                if (gitScenario) {
                  return { kind: "inside", root: scenario === "target-git-cwd-jj-repository" ? "/target" : "/repo" };
                }
                return { kind: "outside" };
              },
              head: async (root: string) => {
                gitHeadDirectories.push(root);
                if (
                  scenario === "git-main" ||
                  scenario === "git-protected-head" ||
                  scenario === "outside-jj-hint-git-main" ||
                  scenario === "notification-throws"
                ) return processResult("main\n");
                if (scenario === "git-multiline-head") return processResult("main\nfeature/policy\n");
                if (scenario === "git-malformed-head") return processResult("feature branch\n");
                if (scenario === "git-detached-head") return processResult("", 1, "");
                return processResult("feature/policy\n");
              },
            },
            jj: {
              run: async (argv: string[], cwd: string) => {
                calls.push(argv);
                jjCwds.push(cwd);
                if (scenario === "target-jj-cwd-other-repository" && cwd !== "/target") {
                  return processResult("/cwd\n");
                }
                if (scenario === "target-git-cwd-jj-repository") {
                  return cwd === "/target" ? jjOutside : processResult("/cwd\n");
                }
                return outputs[jjIndex++] ?? processResult("", 99, "unexpected jj probe");
              },
            },
            notification: {
              notify: (message: string) => {
                if (scenario === "notification-throws") throw new Error("notification unavailable");
                notifications.push(message);
              },
            },
          };
        }

        function check(name: string, actual: string, expected: string, reason: string, expectedReason?: string) {
          if (actual !== expected || (expectedReason !== undefined && !reason.includes(expectedReason))) {
            failures.push(name + ": expected " + expected + (expectedReason ? " containing " + JSON.stringify(expectedReason) : "") + ", got " + actual + " " + JSON.stringify(reason));
          }
        }

        for (const entry of cases) {
          try {
            if (entry.kind === "shell") {
              if (entry.custom && !hasPermissionPolicy) {
                failures.push(entry.name + ": missing permission-rules policy");
                continue;
              }
              if (entry.headless === true) {
                const gated = await runGateHandler({
                  rulesSource: entry.custom ? process.env.PERMISSION_RULES_MODULE : undefined,
                  command: entry.command,
                  hasUI: false,
                });
                check(entry.name, gated.decision, entry.expected, gated.reason, entry.reason);
                continue;
              }
              const result = classify(entry.command, entry.custom ? customConfig : {}, {});
              check(entry.name, result.decision, entry.expected, result.reason, entry.reason);
              continue;
            }
            if (entry.kind === "shell-error") {
              const gated = await runGateHandler({
                rulesInline:
                  'export default () => ({ extraRules: [{ label: "synthetic throwing rule", action: "prompt", test: () => { throw new Error("synthetic parser fault"); } }] });\n',
                command: "printf safe",
                hasUI: false,
              });
              check(entry.name, gated.decision, entry.expected, gated.reason, entry.reason);
              continue;
            }
            if (entry.kind === "project") {
              const result =
                entry.headless === true
                  ? await runGateHandler({
                      projectConfig: entry.project,
                      command: entry.command,
                      hasUI: false,
                    })
                  : classify(entry.command, {}, entry.project);
              check(entry.name, result.decision, entry.expected, result.reason);
              if (!result.warnings.some((warning: string) => warning.includes(entry.warning))) {
                failures.push(entry.name + ": expected warning containing " + JSON.stringify(entry.warning) + ", got " + JSON.stringify(result.warnings));
              }
              continue;
            }
            if (editPolicyKinds.has(entry.kind) && !hasEditPolicy) {
              failures.push(entry.name + ": missing edit-write policy");
              continue;
            }
            if (entry.kind === "git-root") {
              if (typeof editModule.parseGitRootResult !== "function") {
                failures.push(entry.name + ": missing Git root result parser");
                continue;
              }
              const result = editModule.parseGitRootResult(entry.result);
              check(
                entry.name,
                result.kind,
                entry.expected,
                result.kind === "invalid" ? result.diagnostic : "",
                entry.reason,
              );
              continue;
            }
            if (entry.kind === "core") {
              const result = editModule.decideEditWrite(entry.input);
              check(entry.name, result.decision, entry.expected, result.reason ?? "", entry.reason);
              continue;
            }
            if (entry.kind === "repository") {
              const calls: string[][] = [];
              const jjCwds: string[] = [];
              const gitRootDirectories: string[] = [];
              const gitHeadDirectories: string[] = [];
              const notifications: string[] = [];
              const capabilities = fakeCapabilities(
                entry.scenario,
                calls,
                jjCwds,
                gitRootDirectories,
                gitHeadDirectories,
                notifications,
              );
              const target = entry.target ?? "/repo/file.ts";
              const cwd = entry.cwd ?? "/repo";
              const input = await editModule.evaluateEditWrite("edit", target, cwd, capabilities);
              check(entry.name, input.decision, entry.expected, input.reason ?? "", entry.reason);
              // A notify decision that announces nothing is a bare allow, which
              // is a different decision from the one this policy declares.
              const expectedNotifications = entry.expected === "notify" ? 1 : 0;
              if (notifications.length !== expectedNotifications) {
                failures.push(entry.name + ": expected " + expectedNotifications + " announcement(s), got " + JSON.stringify(notifications));
              }
              for (const argv of calls) {
                if (argv[0] !== "jj" || argv[1] !== "--ignore-working-copy") {
                  failures.push(entry.name + ": jj argv does not start with jj --ignore-working-copy: " + JSON.stringify(argv));
                }
              }
              if (calls.length > 0 && entry.expectedJjArgv == null) {
                failures.push(entry.name + ": jj-invoking repository scenario lacks an exact argv oracle");
              } else if (
                entry.expectedJjArgv !== null &&
                JSON.stringify(calls) !== JSON.stringify(entry.expectedJjArgv)
              ) {
                failures.push(
                  entry.name + ": expected exact jj argv " + JSON.stringify(entry.expectedJjArgv) +
                  ", got " + JSON.stringify(calls),
                );
              }
              if (entry.expectedProbeCwd !== undefined && jjCwds.some((probeCwd) => probeCwd !== entry.expectedProbeCwd)) {
                failures.push(entry.name + ": expected every jj probe cwd to be " + JSON.stringify(entry.expectedProbeCwd) + ", got " + JSON.stringify(jjCwds));
              }
              if (
                entry.expectedGitRootDirectory !== undefined &&
                (gitRootDirectories.length !== 1 || gitRootDirectories[0] !== entry.expectedGitRootDirectory)
              ) {
                failures.push(entry.name + ": expected Git root probe directory " + JSON.stringify(entry.expectedGitRootDirectory) + ", got " + JSON.stringify(gitRootDirectories));
              }
              if (
                entry.expectedGitHeadDirectory !== undefined &&
                (gitHeadDirectories.length !== 1 || gitHeadDirectories[0] !== entry.expectedGitHeadDirectory)
              ) {
                failures.push(entry.name + ": expected Git head probe directory " + JSON.stringify(entry.expectedGitHeadDirectory) + ", got " + JSON.stringify(gitHeadDirectories));
              }
              continue;
            }
            if (entry.kind === "normalize") {
              if (typeof editModule.normalizeToolPath !== "function") {
                failures.push(entry.name + ": missing tool path normalizer");
                continue;
              }
              const actual = editModule.normalizeToolPath(entry.input, "/home/tester");
              check(entry.name, actual ?? "(undefined)", entry.expected, "");
              continue;
            }
            if (entry.kind === "classification") {
              if (typeof editModule.inspectRepository !== "function") {
                failures.push(entry.name + ": missing repository inspector");
                continue;
              }
              const calls: string[][] = [];
              const jjCwds: string[] = [];
              const capabilities = fakeCapabilities(entry.scenario, calls, jjCwds);
              const target = entry.target ?? "/repo/file.ts";
              const state = await editModule.inspectRepository(target, entry.inspectionDirectory ?? "/repo", capabilities);
              check(
                entry.name,
                state.kind,
                entry.expected,
                state.kind === "invalid" ? state.diagnostic : "",
                entry.reason,
              );
              continue;
            }
            if (entry.kind === "adapter") {
              if (entry.scenario === "registration") {
                const registrations: Array<{ event: string; handler: unknown }> = [];
                editModule.default({
                  on: (event: string, handler: unknown) => registrations.push({ event, handler }),
                });
                const valid = registrations.length === 1
                  && registrations[0].event === "tool_call"
                  && typeof registrations[0].handler === "function";
                check(entry.name, valid ? "pass" : "block", entry.expected, JSON.stringify(registrations));
                continue;
              }
              const calls: string[][] = [];
              const notifications: string[] = [];
              const capabilities = fakeCapabilities(entry.scenario, calls, [], [], [], notifications);
              if (entry.scenario === "capability-missing") {
                delete (capabilities as { filesystem?: unknown }).filesystem;
              }
              const options = entry.scenario === "core-throws"
                ? { decide: () => { throw new Error("synthetic core fault"); } }
                : {};
              const capabilityFactory = entry.scenario === "capability-factory-throws"
                ? () => { throw new Error("synthetic capability factory fault"); }
                : () => capabilities;
              const handler = editModule.createEditWriteToolCallHandler(capabilityFactory, options);
              const context = {
                cwd: "/repo",
                ui: { notify: (message: string) => notifications.push(message) },
              };
              const result = await handler({ toolName: entry.tool, toolCallId: "call-1", input: entry.input }, context);
              const actual = result?.block === true ? "block" : "pass";
              check(entry.name, actual, entry.expected, result?.reason ?? "", entry.reason);
              if (entry.expectedNotification !== undefined) {
                if (!notifications.some((message: string) => message.includes(entry.expectedNotification))) {
                  failures.push(entry.name + ": expected an announcement containing " + JSON.stringify(entry.expectedNotification) + ", got " + JSON.stringify(notifications));
                }
              }
              continue;
            }
            failures.push(entry.name + ": unrecognized policy case kind " + JSON.stringify(entry.kind));
          } catch (error) {
            failures.push(entry.name + ": uncaught exception: " + String(error));
          }
        }

        if (failures.length > 0) {
          for (const failure of failures) console.error("FAIL: " + failure);
          console.error(failures.length + " pi-agent-environment policy case(s) failed");
          process.exit(1);
        }
        for (const entry of cases) console.log("PASS: " + entry.name);
        console.log(cases.length + " pi-agent-environment policy cases passed");
      '';
    in
    {
      checks = {
        pi-agent-environment-structural = mkCheck {
          name = "pi-agent-environment";
          actual = {
            piModulePi083References = pi083References piModuleText;
            inherit piReconnaissancePresent;
            piReconnaissancePi083References = pi083References piReconnaissanceText;
            deployedPiCandidateCount = builtins.length deployedPiCandidates;
            inherit deployedPiIsOuterWrapper;
            canonicalSkillImmutable = homeFileImmutable ".factory/skills/using-superpowers";
            extensionPackageName = if extensionPackage == null then null else lib.getName extensionPackage;
            inherit positiveExtensions negativeExtensions;
            packageSkills = if extensionEntry == null then [ ] else extensionEntry.skills or [ ];
            packagePrompts = if extensionEntry == null then [ ] else extensionEntry.prompts or [ ];
            packageThemes = if extensionEntry == null then [ ] else extensionEntry.themes or [ ];
            # Presence of the three keys is load-bearing beyond their values:
            # pi's package-manager treats an omitted key as autoload-everything
            # and an empty list as disable-everything, so the `[ ]` declarations
            # in modules/home/ai/pi/default.nix must survive a pin bump.
            packageResourceKindsDeclared =
              if extensionEntry == null then
                [ ]
              else
                builtins.filter (kind: builtins.hasAttr kind extensionEntry) [
                  "skills"
                  "prompts"
                  "themes"
                ];
            extraPackages = map lib.getName piConfig.extraPackages;
            compactionRetained =
              compactionSource != null
              && lib.any (entry: !builtins.isAttrs entry && entry == compactionSource) packageEntries;
            # pi's `packages` is the shared list plus aiAgentSettings.piOnlyPackages.
            # This claims only that pi receives the vim entry through that channel;
            # modules/checks/atomic-agent-environment.nix owns the other half, that
            # atomic does not.
            vimRetained =
              vimSource != null && lib.any (entry: !builtins.isAttrs entry && entry == vimSource) packageEntries;
            vimViaPiOnlyChannel = builtins.elem vimSource (
              map toString homeConfig.aiAgentSettings.piOnlyPackages
            );
            inherit globalInstructionsNixOwned piSpecificSkillsPresent;
            canonicalSkills = if canonicalSkillsScript == "" then null else "~/.agents/skills";
            slowModeSettingsShape = builtins.attrNames piConfig.settings;
            settingsActivation = {
              afterWriteBoundary = builtins.elem "writeBoundary" (settingsActivation.after or [ ]);
              copyCommand = lib.hasInfix "install -Dm644" settingsActivationData;
              immutableHomeFileEnabled = homeFileEnabled settingsTarget;
              target =
                if lib.hasInfix settingsTarget settingsActivationData then "~/.pi/agent/settings.json" else null;
            };
            inherit runtimeStateOutsideImmutableLinks;
            immutableResourceTargets = {
              policy = immutablePolicyTargets;
              theme = lib.optional (homeFileImmutable themeTarget) "~/.pi/agent/themes/catppuccin-mocha.json";
              extensions = immutableExtensionTargets;
              globalInstructions = lib.optional globalInstructionsNixOwned "~/.pi/agent/AGENTS.md";
            };
            policySourcesCheckedIn = {
              permissionRules = homeFileSourceIs permissionRulesTarget permissionRulesPath;
              editWritePolicy = homeFileSourceIs editWritePolicyTarget editWritePolicyPath;
            };
            # atomic inherits ~/.pi/agent as a configuration root unconditionally
            # and scans its extensions directory, so a file written only for pi
            # runs under atomic unless atomic's own settings refuse it by name.
            # Nothing else in this repository observes that coupling, and the
            # edit/write policy reached atomic through it for three days.
            piOnlyExtensionScope =
              let
                declared = homeConfig.aiAgentSettings.piOnlyExtensions;
                forceExcludes = homeConfig.programs.atomic.settings.extensions or [ ];
              in
              {
                inherit declared;
                atomicForceExcludes = forceExcludes;
                everyDeclaredExcluded = lib.all (
                  extension: builtins.elem "-extensions/${extension}" forceExcludes
                ) declared;
                # atomic matches a force-exclude against the path relative to the
                # scanned configuration root, never the basename, so the bare
                # spelling loads the extension it claims to refuse.
                noBareBasenameSpelling =
                  !lib.any (entry: lib.any (extension: entry == "-${extension}") declared) forceExcludes;
              };
            contextNixOwned = piConfig.context == homeConfig.programs.agents-md.settings.text;
            theme = {
              contentName = themeJson.name or null;
              selected = piConfig.settings.theme or null;
              target =
                if homeFileAt themeTarget == null then null else "~/.pi/agent/themes/catppuccin-mocha.json";
              targetImmutable = homeFileImmutable themeTarget;
              sourceCheckedIn = homeFileSourceIs themeTarget themePath;
              sha256 = if themePresent then builtins.hashFile "sha256" themePath else null;
              standalonePackagePresent = lib.any (name: lib.hasInfix "catppuccin-mocha" name) (
                builtins.attrNames self'.packages
              );
            };
          };
          expected = {
            piModulePi083References = [ ];
            piReconnaissancePresent = true;
            piReconnaissancePi083References = [ ];
            deployedPiCandidateCount = 1;
            deployedPiIsOuterWrapper = true;
            canonicalSkillImmutable = true;
            extensionPackageName = "pi-agent-extensions";
            positiveExtensions = [
              "direnv/index.ts"
              "permission-gate/index.ts"
              "questionnaire/index.ts"
              "slow-mode/index.ts"
              "stash/index.ts"
              "statusline/index.ts"
            ];
            negativeExtensions = [
              "-fetch/index.ts"
              "-notify/index.ts"
            ];
            packageSkills = [ ];
            packagePrompts = [ ];
            packageThemes = [ ];
            packageResourceKindsDeclared = [
              "skills"
              "prompts"
              "themes"
            ];
            extraPackages = [
              "direnv"
              "diffutils"
              "git"
              "jujutsu"
              "rip2"
            ];
            compactionRetained = true;
            vimRetained = true;
            vimViaPiOnlyChannel = true;
            globalInstructionsNixOwned = true;
            canonicalSkills = "~/.agents/skills";
            piSpecificSkillsPresent = false;
            slowModeSettingsShape = [
              "enableInstallTelemetry"
              "hideThinkingBlock"
              "packages"
              "theme"
            ];
            settingsActivation = {
              afterWriteBoundary = true;
              copyCommand = true;
              immutableHomeFileEnabled = false;
              target = "~/.pi/agent/settings.json";
            };
            runtimeStateOutsideImmutableLinks = [
              "settings"
              "sessions"
              "compaction"
              "authentication"
              "project-trust"
              "model-selection"
              "thinking-preferences"
              "extension-state"
            ];
            immutableResourceTargets = {
              policy = [
                "pi-agent-extensions/permission-gate/index.ts"
                "~/.config/pi-agent-extensions/permission-gate/rules.ts"
                "~/.pi/agent/extensions/edit-write-policy.ts"
              ];
              theme = [ "~/.pi/agent/themes/catppuccin-mocha.json" ];
              extensions = [
                "pi-agent-extensions/direnv/index.ts"
                "pi-agent-extensions/permission-gate/index.ts"
                "pi-agent-extensions/questionnaire/index.ts"
                "pi-agent-extensions/slow-mode/index.ts"
                "pi-agent-extensions/stash/index.ts"
                "pi-agent-extensions/statusline/index.ts"
              ];
              globalInstructions = [ "~/.pi/agent/AGENTS.md" ];
            };
            policySourcesCheckedIn = {
              permissionRules = true;
              editWritePolicy = true;
            };
            piOnlyExtensionScope = {
              declared = [ "edit-write-policy.ts" ];
              atomicForceExcludes = [ "-extensions/edit-write-policy.ts" ];
              everyDeclaredExcluded = true;
              noBareBasenameSpelling = true;
            };
            contextNixOwned = true;
            theme = {
              contentName = "catppuccin-mocha";
              selected = "catppuccin-mocha";
              target = "~/.pi/agent/themes/catppuccin-mocha.json";
              targetImmutable = true;
              sourceCheckedIn = true;
              sha256 = "5858d086e155246d48e5b7a2ac372988fe2d1a028d2b77b5f0a7670088a8642b";
              standalonePackagePresent = false;
            };
          };
        };

        pi-agent-environment-policy =
          pkgs.runCommand "pi-agent-environment-policy"
            {
              nativeBuildInputs = [
                pkgs.bun
                pkgs.typescript
              ];
              BUN_CONFIG_NO_INSTALL = "1";
              PERMISSION_GATE_ROOT = "${extensionPackage}/permission-gate";
              PERMISSION_RULES_MODULE = permissionRulesModule;
              EDIT_WRITE_POLICY_MODULE = editWritePolicyModule;
              POLICY_CASES = policyCases;
              POLICY_HARNESS = policyHarness;
              POLICY_TYPE_DECLARATIONS = policyTypeDeclarations;
              POLICY_TSCONFIG = policyTsconfig;
            }
            ''
              set -o pipefail
              mkdir typecheck
              ln -s "$PERMISSION_GATE_ROOT" typecheck/permission-gate
              ln -s "$PERMISSION_RULES_MODULE" typecheck/permission-rules.ts
              ln -s "$EDIT_WRITE_POLICY_MODULE" typecheck/edit-write-policy.ts
              ln -s "$POLICY_TYPE_DECLARATIONS" typecheck/external.d.ts
              ln -s "$POLICY_HARNESS" typecheck/policy-test.ts
              ln -s "$POLICY_TSCONFIG" typecheck/tsconfig.json
              tsc -p typecheck/tsconfig.json
              bun "$POLICY_HARNESS"
              touch "$out"
            '';

        pi-agent-environment-smoke =
          let
            jsonFormat = pkgs.formats.json { };
            # ~/.agents/skills is activation-delivered
            # (modules/home/ai/skills/default.nix, home.activation
            # .agentsSkillsRealFiles) and so has no home.file entry to name,
            # while this regulator must take its fixture resources from
            # evaluated derivation paths rather than from parsed activation
            # shell. The Droid .factory/skills entry is built from the same
            # fileSkills set, so it is the same composed tree under a nameable
            # key — not a second, Pi-specific skill sink.
            canonicalSkillSource = requiredHomeFileSource ".factory/skills/using-superpowers";
            settingsFixture = jsonFormat.generate "pi-agent-environment-smoke-settings.json" {
              enableInstallTelemetry = false;
              packages = packageEntries;
            };
            modelsFixture = jsonFormat.generate "pi-agent-environment-smoke-models.json" {
              providers.smoke-local = {
                baseUrl = "http://127.0.0.1:9/v1";
                api = "openai-completions";
                models = [ { id = "smoke-model"; } ];
              };
            };
            smokeDriver = pkgs.writeText "pi-agent-environment-smoke-driver.py" ''
              import json
              import os
              from pathlib import Path
              import signal
              import subprocess


              def fail(message):
                  raise AssertionError(message)


              requests = [
                  {"id": "state", "type": "get_state"},
                  {"id": "commands", "type": "get_commands"},
              ]
              home = Path(os.environ["SMOKE_HOME"])
              agent_dir = home / ".pi" / "agent"
              argv = [
                  os.environ["PI_EXECUTABLE"],
                  "--mode",
                  "rpc",
                  "--no-session",
                  "--no-approve",
                  "--model",
                  "smoke-local/smoke-model",
              ]
              launch_env = {
                  "HOME": str(home),
                  "PI_CODING_AGENT_DIR": str(agent_dir),
                  "XDG_CONFIG_HOME": str(home / ".config"),
                  "XDG_DATA_HOME": str(home / ".local" / "share"),
                  "XDG_CACHE_HOME": str(home / ".cache"),
                  "TMPDIR": os.environ["SMOKE_TMPDIR"],
                  "PI_OFFLINE": "1",
                  "PI_STATUSLINE": "minimal",
              }
              request_bytes = b"".join(
                  json.dumps(request, separators=(",", ":")).encode() + b"\n"
                  for request in requests
              )
              process = subprocess.Popen(
                  argv,
                  cwd=os.environ["SMOKE_PROJECT"],
                  env=launch_env,
                  stdin=subprocess.PIPE,
                  stdout=subprocess.PIPE,
                  stderr=subprocess.PIPE,
                  start_new_session=True,
              )
              try:
                  stdout, stderr = process.communicate(input=request_bytes, timeout=20)
              except subprocess.TimeoutExpired as error:
                  try:
                      os.killpg(process.pid, signal.SIGKILL)
                  except ProcessLookupError:
                      pass
                  process.communicate()
                  raise AssertionError("Pi did not exit within 20 seconds after stdin closure") from error

              if process.returncode != 0:
                  fail(
                      f"Pi exited {process.returncode}: "
                      f"{stderr.decode('utf-8', 'replace')}"
                  )

              records = []
              for index, line in enumerate(stdout.splitlines(), start=1):
                  try:
                      record = json.loads(line)
                  except (UnicodeDecodeError, json.JSONDecodeError) as error:
                      fail(f"Pi RPC record {index} is malformed: {error}")
                  if not isinstance(record, dict):
                      fail(f"Pi RPC record {index} is not an object")
                  records.append(record)

              extension_errors = [
                  record for record in records if record.get("type") == "extension_error"
              ]
              if extension_errors:
                  fail(f"selected extension failed to load: {extension_errors}")

              responses = {
                  record.get("id"): record
                  for record in records
                  if record.get("type") == "response"
              }
              for request in requests:
                  response = responses.get(request["id"])
                  if response is None or response.get("success") is not True:
                      fail(f"missing successful {request['type']} response: {response}")

              state = responses["state"].get("data")
              if not isinstance(state, dict):
                  fail(f"get_state returned invalid data: {state}")
              model = state.get("model")
              selected_model = (
                  model.get("provider"),
                  model.get("id"),
              ) if isinstance(model, dict) else None
              if selected_model != ("smoke-local", "smoke-model"):
                  fail(f"explicit synthetic model selection was not reported: {selected_model}")
              if state.get("sessionFile") is not None:
                  fail(f"--no-session reported a session file: {state['sessionFile']}")

              command_data = responses["commands"].get("data")
              command_rows = command_data.get("commands") if isinstance(command_data, dict) else None
              if not isinstance(command_rows, list):
                  fail(f"get_commands returned invalid data: {command_data}")
              commands = {
                  row.get("name"): row.get("source")
                  for row in command_rows
                  if isinstance(row, dict)
              }
              required_extension_commands = {"direnv", "gate", "slow-mode", "statusline"}
              missing_extension_commands = sorted(
                  name
                  for name in required_extension_commands
                  if commands.get(name) != "extension"
              )
              if missing_extension_commands:
                  fail(f"missing required extension commands: {missing_extension_commands}")
              skill_command = "skill:using-superpowers"
              if commands.get(skill_command) != "skill":
                  fail(f"missing canonical skill command: {skill_command}")

              print(f"pi_executable={argv[0]}")
              print(f"selected_model={selected_model[0]}/{selected_model[1]}")
              print(f"required_extension_commands={sorted(required_extension_commands)}")
              print(f"canonical_skill_command={skill_command}")
              print("extension_errors=0")
              print("session_file=absent_or_null")
              print("stdin_closed=true")
              print(f"exit_status={process.returncode}")
            '';
          in
          pkgs.runCommand "pi-agent-environment-smoke"
            {
              nativeBuildInputs = [ pkgs.python3 ];
              PI_EXECUTABLE = deployedPiExecutable;
              DEPLOYED_PI_CANDIDATE_COUNT = toString (builtins.length deployedPiCandidates);
              SETTINGS_FIXTURE = settingsFixture;
              MODELS_FIXTURE = modelsFixture;
              CANONICAL_SKILL_SOURCE = if canonicalSkillSource == null then "" else canonicalSkillSource;
            }
            ''
              if [ -z "$PI_EXECUTABLE" ]; then
                echo "pi-agent-environment-smoke: no deployed Pi outer wrapper to run" >&2
                echo "  home.packages entries with meta.mainProgram = pi: $DEPLOYED_PI_CANDIDATE_COUNT" >&2
                echo >&2
                echo "This check exercises the wrapper Home Manager actually installs, so it" >&2
                echo "needs exactly one such candidate and that candidate must differ from" >&2
                echo "programs.pi-coding-agent.package." >&2
                echo >&2
                echo "Remediation: with a count other than 1, reconcile home.packages in" >&2
                echo "modules/home/ai/pi/default.nix so the Pi wrapper is the only main" >&2
                echo "program named pi. With a count of 1, the outer wrapper collapsed onto" >&2
                echo "programs.pi-coding-agent.package and the module no longer wraps it." >&2
                exit 1
              fi
              if [ -z "$CANONICAL_SKILL_SOURCE" ]; then
                echo "pi-agent-environment-smoke: no immutable Home Manager resource at" >&2
                echo "  .factory/skills/using-superpowers" >&2
                echo >&2
                echo "The fixture seeds ~/.agents/skills from that home.file entry, which the" >&2
                echo ".factory/skills mapping in modules/home/ai/skills/default.nix produces" >&2
                echo "from the same composed skill set activation delivers." >&2
                echo >&2
                echo "Remediation: restore that mapping in modules/home/ai/skills/default.nix," >&2
                echo "or repoint canonicalSkillSource in this file at the entry replacing it." >&2
                exit 1
              fi
              home="$TMPDIR/home"
              agent="$home/.pi/agent"
              mkdir -p \
                "$agent" \
                "$home/.agents/skills/using-superpowers" \
                "$home/.config" \
                "$home/.local/share" \
                "$home/.cache" \
                "$TMPDIR/pi-tmp" \
                "$TMPDIR/project"
              install -m644 "$SETTINGS_FIXTURE" "$agent/settings.json"
              install -m644 "$MODELS_FIXTURE" "$agent/models.json"
              cp -RL --no-preserve=mode \
                "$CANONICAL_SKILL_SOURCE/." \
                "$home/.agents/skills/using-superpowers/"
              SMOKE_HOME="$home" \
              SMOKE_PROJECT="$TMPDIR/project" \
              SMOKE_TMPDIR="$TMPDIR/pi-tmp" \
                python3 ${smokeDriver} | tee "$out"
            '';
      };
    };
}
