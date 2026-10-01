# Behavioural check for the managed-config program behind `managedConfigs`.
#
# Each row runs the program against real files in a fresh directory and asserts
# its exit status, the written content, and its stderr. Spec targets and
# declared files are given relative to the row directory and made absolute at
# run time.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      program = lib.getExe (self.lib.managedConfigProgram pkgs);

      sentinel = "SENTINEL-VALUE-must-not-leak";

      mkSpec =
        index: spec:
        let
          declaredFile = "declared-${toString index}.json";
        in
        ''
          printf '%s' ${lib.escapeShellArg (builtins.toJSON spec.declared)} > ${declaredFile}
          jq -n --arg root "$PWD" \
            --argjson spec ${
              lib.escapeShellArg (
                builtins.toJSON (
                  {
                    fileMode = "0644";
                    appOwned = [ ];
                    externalPaths = [ ];
                  }
                  // removeAttrs spec [ "declared" ]
                )
              )
            } \
            '$spec + { target: ($root + "/" + $spec.target), declared: ($root + "/${declaredFile}") }' \
            > spec-${toString index}.json
        '';

      # `existing` maps row-relative paths to initial file contents. `stderr`
      # lines are matched exactly, with @ROOT@ standing for the row directory.
      # `verify` runs after the program.
      row =
        {
          name,
          existing ? { },
          specs,
          status,
          stderr ? [ ],
          verify ? "",
        }:
        ''
          echo "--- ${name}"
          rm -rf "$TMPDIR/row" && mkdir "$TMPDIR/row" && cd "$TMPDIR/row"
          ${lib.concatStrings (
            lib.mapAttrsToList (path: content: ''
              mkdir -p "$(dirname ${lib.escapeShellArg path})"
              printf '%s' ${lib.escapeShellArg content} > ${lib.escapeShellArg path}
            '') existing
          )}
          ${lib.concatStrings (lib.imap0 mkSpec specs)}
          status=0
          ${program} ${
            lib.concatMapStringsSep " " (i: "spec-${toString i}.json") (lib.range 0 (lib.length specs - 1))
          } > stdout 2> stderr || status=$?
          cat stderr
          fail() { echo "row '${name}': $*" >&2; exit 1; }
          [ "$status" = ${toString status} ] || fail "exit status $status, expected ${toString status}"
          [ "$(wc -l < stderr)" = ${toString (lib.length stderr)} ] \
            || fail "expected exactly ${toString (lib.length stderr)} stderr line(s)"
          ${lib.concatMapStrings (line: ''
            expected=${lib.escapeShellArg line}
            expected="''${expected//@ROOT@/$PWD}"
            grep -qxF "$expected" stderr || fail "missing stderr line: $expected"
          '') stderr}
          ! grep -qF ${lib.escapeShellArg sentinel} stderr || fail "a value leaked to stderr"
          ${verify}
        '';

      # Asserts the file at `path` parses (in `format`) to exactly `value`.
      hasContent = format: path: value: ''
        [ "$(yq -p ${format} -o json -I0 '.' ${path} | jq -cS .)" = ${lib.escapeShellArg (builtins.toJSON value)} ] || fail "${path}: content $(yq -p ${format} -o json -I0 '.' ${path}), expected "${lib.escapeShellArg (builtins.toJSON value)}
      '';

      hasMode = path: mode: ''
        [ "$(stat -c %a ${path})" = ${mode} ] || fail "${path}: mode $(stat -c %a ${path}), expected ${mode}"
      '';

      replaceRow =
        format: existing:
        row {
          name = "${format} replace drops and reports undeclared keys";
          existing."cfg/file.${format}" = existing;
          specs = [
            {
              name = "t";
              target = "cfg/file.${format}";
              inherit format;
              declared = {
                a.b = 1;
                c = "x";
              };
            }
          ];
          status = 0;
          stderr = [ "managed-config t: dropped undeclared keys: a.old, list[].k, stale" ];
          verify =
            hasContent format "cfg/file.${format}" {
              a.b = 1;
              c = "x";
            }
            + hasMode "cfg/file.${format}" "644";
        };
    in
    {
      checks.managed-config-rehearsal =
        pkgs.runCommand "managed-config-rehearsal"
          {
            nativeBuildInputs = [
              pkgs.jq
              pkgs.yq-go
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.diffutils
            ];
            meta.description = "behavioural check: managed-config program";
          }
          ''
            ${replaceRow "json" ''
              {"a":{"b":2,"old":"${sentinel}"},"c":"x","stale":"${sentinel}","list":[{"k":1},{"k":2}]}
            ''}
            ${replaceRow "yaml" ''
              a:
                b: 2
                old: ${sentinel}
              c: x
              stale: ${sentinel}
              list:
                - k: 1
                - k: 2
            ''}
            ${replaceRow "toml" ''
              c = "x"
              stale = "${sentinel}"

              [a]
              b = 2
              old = "${sentinel}"

              [[list]]
              k = 1

              [[list]]
              k = 2
            ''}

            ${row {
              name = "appOwned nested paths are preserved";
              existing."cfg/config.yaml" = ''
                host:
                  host_id: abc123
                  name: old
                server:
                  url: https://example.invalid
                  token: ${sentinel}
                stale: ${sentinel}
              '';
              specs = [
                {
                  name = "t";
                  target = "cfg/config.yaml";
                  format = "yaml";
                  appOwned = [
                    "host.host_id"
                    "server"
                  ];
                  declared = {
                    host.name = "new";
                    x = 1;
                  };
                }
              ];
              status = 0;
              stderr = [ "managed-config t: dropped undeclared keys: stale" ];
              verify = hasContent "yaml" "cfg/config.yaml" {
                host = {
                  host_id = "abc123";
                  name = "new";
                };
                server = {
                  token = sentinel;
                  url = "https://example.invalid";
                };
                x = 1;
              };
            }}

            ${row {
              name = "appOwned absent from the old file is not invented";
              existing."cfg/config.json" = ''{"x":0}'';
              specs = [
                {
                  name = "present";
                  target = "cfg/config.json";
                  format = "json";
                  appOwned = [
                    "host.host_id"
                    "version"
                  ];
                  declared.x = 1;
                }
                {
                  name = "missing";
                  target = "cfg/new.json";
                  format = "json";
                  appOwned = [ "version" ];
                  declared.x = 1;
                }
              ];
              status = 0;
              verify =
                hasContent "json" "cfg/config.json" { x = 1; } + hasContent "json" "cfg/new.json" { x = 1; };
            }}

            ${row {
              name = "externalPaths are excluded from the drop report";
              existing."cfg/config.toml" = ''
                model = "m"
                gone = "${sentinel}"

                [features]
                hooks = true
                other = 1

                [[hooks.PreToolUse]]
                command = "${sentinel}"
              '';
              specs = [
                {
                  name = "t";
                  target = "cfg/config.toml";
                  format = "toml";
                  externalPaths = [
                    "hooks"
                    "features.hooks"
                  ];
                  declared.model = "m";
                }
              ];
              status = 0;
              stderr = [ "managed-config t: dropped undeclared keys: features.other, gone" ];
              verify = hasContent "toml" "cfg/config.toml" { model = "m"; };
            }}

            ${row {
              name = "unreadable target with appOwned is refused and untouched";
              existing."cfg/config.json" = ''{"version": "${sentinel}"'';
              specs = [
                {
                  name = "t";
                  target = "cfg/config.json";
                  format = "json";
                  appOwned = [ "version" ];
                  declared.x = 1;
                }
              ];
              status = 1;
              stderr = [
                "managed-config t: @ROOT@/cfg/config.json is unreadable or not a mapping; left untouched"
              ];
              verify = ''
                printf '%s' ${lib.escapeShellArg ''{"version": "${sentinel}"''} > expected
                cmp expected cfg/config.json || fail "target was modified"
              '';
            }}

            ${row {
              name = "non-mapping target with appOwned is refused and untouched";
              existing."cfg/config.yaml" = ''
                - ${sentinel}
              '';
              specs = [
                {
                  name = "t";
                  target = "cfg/config.yaml";
                  format = "yaml";
                  appOwned = [ "version" ];
                  declared.x = 1;
                }
              ];
              status = 1;
              stderr = [
                "managed-config t: @ROOT@/cfg/config.yaml is unreadable or not a mapping; left untouched"
              ];
              verify = ''
                printf '%s\n' ${lib.escapeShellArg "- ${sentinel}"} > expected
                cmp expected cfg/config.yaml || fail "target was modified"
              '';
            }}

            ${row {
              name = "explicit null target with appOwned is refused and untouched";
              existing."cfg/config.yaml" = "null\n";
              existing."cfg/config.json" = "null";
              specs = [
                {
                  name = "y";
                  target = "cfg/config.yaml";
                  format = "yaml";
                  appOwned = [ "version" ];
                  declared.x = 1;
                }
                {
                  name = "j";
                  target = "cfg/config.json";
                  format = "json";
                  appOwned = [ "version" ];
                  declared.x = 1;
                }
              ];
              status = 1;
              stderr = [
                "managed-config y: @ROOT@/cfg/config.yaml is unreadable or not a mapping; left untouched"
                "managed-config j: @ROOT@/cfg/config.json is unreadable or not a mapping; left untouched"
              ];
              verify = ''
                [ "$(cat cfg/config.yaml)" = null ] || fail "yaml target was modified"
                [ "$(cat cfg/config.json)" = null ] || fail "json target was modified"
              '';
            }}

            ${row {
              name = "empty target with appOwned reads as an empty mapping";
              existing."cfg/config.yaml" = "\n";
              specs = [
                {
                  name = "t";
                  target = "cfg/config.yaml";
                  format = "yaml";
                  appOwned = [ "version" ];
                  declared.x = 1;
                }
              ];
              status = 0;
              verify = hasContent "yaml" "cfg/config.yaml" { x = 1; };
            }}

            ${row {
              name = "unreadable target without appOwned is replaced with a notice";
              existing."cfg/config.json" = ''{"a": "${sentinel}"'';
              specs = [
                {
                  name = "t";
                  target = "cfg/config.json";
                  format = "json";
                  declared.x = 1;
                }
              ];
              status = 0;
              stderr = [ "managed-config t: replaced unreadable @ROOT@/cfg/config.json" ];
              verify = hasContent "json" "cfg/config.json" { x = 1; };
            }}

            ${row {
              name = "fileMode is applied";
              existing."cfg/config.yaml" = "x: 0\n";
              specs = [
                {
                  name = "t";
                  target = "cfg/config.yaml";
                  format = "yaml";
                  fileMode = "0600";
                  declared.x = 1;
                }
              ];
              status = 0;
              verify = hasContent "yaml" "cfg/config.yaml" { x = 1; } + hasMode "cfg/config.yaml" "600";
            }}

            ${row {
              name = "a failing spec does not stop later specs";
              existing."cfg/bad.json" = "not json";
              specs = [
                {
                  name = "bad";
                  target = "cfg/bad.json";
                  format = "json";
                  appOwned = [ "version" ];
                  declared.x = 1;
                }
                {
                  name = "good";
                  target = "cfg/good.yaml";
                  format = "yaml";
                  declared.y = 2;
                }
              ];
              status = 1;
              stderr = [
                "managed-config bad: @ROOT@/cfg/bad.json is unreadable or not a mapping; left untouched"
              ];
              verify = ''
                [ "$(cat cfg/bad.json)" = "not json" ] || fail "failing target was modified"
              ''
              + hasContent "yaml" "cfg/good.yaml" { y = 2; };
            }}

            ${row {
              name = "missing parent directories are created";
              specs = [
                {
                  name = "t";
                  target = "deep/a/b/settings.json";
                  format = "json";
                  declared.z = true;
                }
              ];
              status = 0;
              verify = hasContent "json" "deep/a/b/settings.json" { z = true; } + ''
                [ -z "$(find deep -name '.*managed-config*')" ] || fail "temporary file left behind"
              '';
            }}

            touch $out
          '';
    };
}
