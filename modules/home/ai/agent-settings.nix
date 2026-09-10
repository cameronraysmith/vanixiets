# Settings shared by the pi-lineage agents in the homeManager.ai aggregate.
#
# atomic reads ~/.pi/agent as a legacy config root, but only while its own root
# is empty: a populated ~/.atomic/agent/settings.json overrides the pi one
# rather than merging with it, so every key atomic is meant to honour has to be
# written into atomic's own file. Holding the values here rather than in either
# consumer is what stops the two files drifting the way they already did once,
# when atomic's first-run wizard copied a snapshot of this package set across
# and then froze it with theme "dark" against the declared catppuccin-mocha.
#
# Where the two agents genuinely need different values, the divergence is named
# here as its own option rather than patched into a consumer, so that one file
# still answers what each agent is given and why.
{ ... }:
let
  content =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      jsonFormat = pkgs.formats.json { };
    in
    {
      options.aiAgentSettings = {
        theme = lib.mkOption {
          type = lib.types.str;
          default = "catppuccin-mocha";
          description = "Theme name written into every pi-lineage agent's settings.json. pi loads it from the vendored ~/.pi/agent/themes/catppuccin-mocha.json; atomic ships the same flavor built in.";
        };

        enableInstallTelemetry = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Anonymous install/update ping on first install and after each changelog-detected update. The store path is replaced by home-manager, so every generation bump would emit one.";
        };

        hideThinkingBlock = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Collapse each run of thinking blocks to a single label rather than
            rendering the full reasoning trace.

            Display only: `defaultThinkingLevel` and the `shift+tab` cycle decide
            whether the model reasons at all, and for Z.AI's thinking format a
            level of `off` sends `thinking: { type: "disabled" }` rather than
            merely hiding what came back. `ctrl+t` (`app.thinking.toggle`)
            expands the whole transcript retroactively.

            Both agents read this key. pi documents it at docs/settings.md and
            renders the collapsed label from
            packages/coding-agent/src/modes/interactive/components/assistant-message.ts;
            atomic carries the same key and renderer.

            pi persists a `ctrl+t` expansion by writing the global settings.json,
            which this module reinstalls wholesale on activation, so the
            expansion lasts until the next generation. A project
            `.pi/settings.json` entry wins over the global file on every read and
            is never rewritten by the toggle, which is the per-repository way to
            keep expansion from becoming the default.
          '';
        };

        packages = lib.mkOption {
          type = lib.types.listOf (lib.types.either lib.types.str jsonFormat.type);
          default = [
            {
              source = "${pkgs.pi-agent-extensions}";
              extensions = [
                "direnv/index.ts"
                "permission-gate/index.ts"
                "questionnaire/index.ts"
                "slow-mode/index.ts"
                "stash/index.ts"
                "statusline/index.ts"
                "-fetch/index.ts"
                "-notify/index.ts"
              ];
              skills = [ ];
              prompts = [ ];
              themes = [ ];
            }
            # Algal declares Pi >=0.80.9 <0.81.0; the fleet evaluates Pi 0.84.1,
            # outside that range. Its fallback compact() argument order still
            # matches exact Pi 0.84.1, while broader API drift remains a
            # calibrated risk. The derivation injects an empty atomic.extensions
            # manifest key, so registering it here contributes nothing to atomic
            # while remaining fully active under pi.
            "${pkgs.pi-openai-server-compaction}"
          ];
          description = "Extension packages registered with every pi-lineage agent, in pi's settings.json packages format.";
        };

        piOnlyPackages = lib.mkOption {
          type = lib.types.listOf (lib.types.either lib.types.str jsonFormat.type);
          default = [ "${pkgs.pi-vim}" ];
          description = ''
            Extension packages registered with pi and with no other pi-lineage agent.

            This is a third divergence channel, distinct from both
            `packagesForAtomic` and `extensionsForAtomic`, and it needs no
            force-exclude at all. `readMergedSettings` deep-merges the two
            settings files (core/settings-storage.ts:70-81) and `deepMergeObjects`
            treats an array as unmergeable (core/settings-merge.ts:3-5), so it
            assigns the override wholesale: atomic declaring its own `packages`
            key shadows pi's outright and an entry here reaches pi alone.
            modules/checks/atomic-agent-environment.nix asserts that atomic keeps
            declaring the key, which is the premise this relies on. Contrast
            `piOnlyExtensions`, which needs force-excludes precisely because the
            `~/.pi/agent/extensions/` directory is scanned unconditionally by both
            agents (core/package-manager-auto-resources.ts:188).

            pi-vim is here because modal editing is pi-only in practice, not
            because atomic fails to load it. Under the npm distribution
            pkgs/by-name/atomic now builds, atomic resolves
            `@earendil-works/pi-coding-agent` through the `_aliases` map and
            pi-vim 0.14.1 loads with exit status 0. What is dead is the editor:
            `ctx.ui.setEditorComponent` is a warn-once stub in every atomic
            distribution, never remoted to the isolated interactive engine child
            the way `EngineCustomUiService` remotes `ctx.ui.custom`, so under
            atomic the extension registers, warns, and leaves the native editor
            in place with no modal keybindings. Registering it there would spend
            a startup warning and a 58 KB source tree to change nothing an
            operator can observe. Restoring it under atomic is an upstream fix
            (route `setEditorComponent` through the existing remoting machinery)
            or a ground-up atomic-native extension on `ctx.ui.custom`, not a
            packaging change here. See
            docs/notes/development/atomic-npm-distribution-compat.md for the
            per-extension load matrix this rests on.
          '';
        };

        atomicExtensionExclusions = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "statusline/index.ts" ];
          description = ''
            Extensions from `packages` that atomic must not load, while pi still does.

            atomic 0.9.13 runs every interactive session's extensions in an isolated
            RPC engine child whose `ctx.ui.setFooter` is a warn-once no-op
            (packages/coding-agent/src/modes/rpc/rpc-extension-ui.ts:232). The
            statusline extension calls it to evict atomic's native footer, so under
            atomic the call warns at startup and the native footer stays docked
            beneath the extension's own bar. atomic exposes no setting that
            suppresses the native footer and no way to disable engine isolation, so
            not loading the extension is the only local remedy. pi runs the same
            extension in-process, where the call is honoured.
          '';
        };

        packagesForAtomic = lib.mkOption {
          type = lib.types.listOf (lib.types.either lib.types.str jsonFormat.type);
          default =
            let
              forceExcludes = map (extension: "-${extension}") config.aiAgentSettings.atomicExtensionExclusions;
              excludeFrom =
                entry:
                if lib.isAttrs entry && entry ? extensions then
                  entry // { extensions = entry.extensions ++ forceExcludes; }
                else
                  entry;
            in
            map excludeFrom config.aiAgentSettings.packages;
          description = ''
            `packages` as atomic receives it, with `atomicExtensionExclusions` appended
            as `-`-prefixed force-excludes to every entry that selects extensions.

            atomic applies force-excludes last and unconditionally
            (packages/coding-agent/src/core/package-manager-resource-patterns.ts:143),
            so an entry named here loses even though the same list includes it by
            name. A pattern matching nothing is inert, so this stays correct if an
            excluded extension later leaves `packages`.
          '';
        };

        piOnlyExtensions = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "edit-write-policy.ts" ];
          description = ''
            Files in pi's own `extensions/` directory that only pi may load, named
            relative to that directory.

            These never appear in `packages`; modules/home/ai/pi/default.nix writes
            them straight into `~/.pi/agent/extensions/`, and atomic picks them up
            anyway. `getAgentDirs` (packages/coding-agent/src/config.ts:376) returns
            `[~/.atomic/agent, ~/.pi/agent]` with no filesystem test -- the only
            escapes are the ATOMIC_CODING_AGENT_DIR environment variable and atomic
            being named pi -- and `addAutoDiscoveredResources`
            (core/package-manager-auto-resources.ts:188) scans both roots' extension
            directories additively. So a populated `~/.atomic/agent` does not
            suppress the pi root, and every `.ts` file placed there runs under both
            agents whether or not either settings file mentions it. This option is
            the only surface on which pi-only scope can be stated.

            edit-write-policy.ts reads a top-level `path` off the tool input, which
            is pi's `edit` and `write` schema. atomic's `write` also has `path`, but
            its `edit` takes a single hashline `input` string under
            `additionalProperties: false`, so a `path` can never reach the policy
            from atomic and every atomic edit was refused as malformed input.
          '';
        };

        extensionsForAtomic = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = map (extension: "-extensions/${extension}") config.aiAgentSettings.piOnlyExtensions;
          description = ''
            atomic's top-level `extensions` settings key, carrying `piOnlyExtensions`
            as `-`-prefixed force-excludes.

            This is a different override channel from `packagesForAtomic`, and the
            two are not interchangeable. A pattern in a `packages` entry is matched
            against the package source directory, while this key is matched against
            each scanned config root
            (core/package-manager-auto-resources.ts:199 passes `configDir` as the
            base), so an entry here is written relative to `~/.pi/agent` and needs
            its `extensions/` segment. The `-` arm compares only that relative path
            or the absolute path and never the basename
            (core/package-manager-resource-patterns.ts matchesAnyExactPattern), so
            the bare `-edit-write-policy.ts` spelling is a silent no-op that loads
            the extension anyway.
          '';
        };
      };
    };
in
{
  flake.modules.homeManager.ai = content;
  flake.modules.homeManager.agent-settings = content;
}
