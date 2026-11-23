# checks.x86_64-linux.agent-skills-index: the Agent Skills discovery index in the
# docs deploy payload (pkgs/by-name/vanixiets-docs-payload) conforms to
# cloudflare/agent-skills-discovery-rfc v0.2.0 and works with the skills CLI
# (vercel-labs/skills, pinned through llm-agents), which implements it in
# src/providers/wellknown.ts.
#
# Conformance, read from the payload's dist/client: the index has exactly the
# `$schema` and `skills` fields, each entry exactly name, type, description,
# url and digest in the RFC's forms, sorted by name; every digest is the
# sha256 of the file its url names, and no other file is published; the names
# are exactly the first-party skill directories and none of the remote skills
# recorded in apm-skills-compose's skills.json; a skill is `skill-md` exactly
# when its directory holds only SKILL.md, and each archive unpacks to its
# directory byte for byte; and a second run of the generator, over a copy of
# the sources with other mtimes and umask, writes the same bytes.
#
# Then the payload is served over loopback and the CLI, run as
# `npx skills add https://infra.cameronraysmith.net` would be, lists every
# skill (fetching each artifact and rejecting any digest mismatch,
# wellknown.ts discoverSkills and fetchArtifactSkillByEntry) and installs an
# archive skill and a SKILL.md-only skill by name, unchanged, recording the
# index's digests in skills-lock.json. llms.txt and robots.txt name the index.
#
# One system: the index does not depend on the platform.
{ inputs, lib, ... }:
{
  perSystem =
    {
      self',
      pkgs,
      system,
      ...
    }:
    let
      payload = self'.packages.vanixiets-docs-payload;
      inherit (payload) index;
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        agent-skills-index =
          pkgs.runCommand "agent-skills-index-check"
            {
              nativeBuildInputs = [
                inputs.llm-agents.packages.${system}.skills
                index.python
                pkgs.jq
                pkgs.unzip
              ];
              inherit payload;
              skills = index.skills;
              composed = ../../pkgs/by-name/apm-skills-compose/skills.json;
              passthru.meta.description = "The docs payload's Agent Skills index conforms to the discovery RFC and the skills CLI installs from it";
            }
            ''
              export HOME="$TMPDIR/home"
              export DISABLE_TELEMETRY=1 DO_NOT_TRACK=1 NO_COLOR=1 TERM=dumb
              mkdir -p "$HOME"
              site="$payload/dist/client"
              published="$site/.well-known/agent-skills"
              index="$published/index.json"
              status=0
              fail() {
                echo "FAIL: $*" >&2
                status=1
              }

              jq -e '
                (keys == ["$schema", "skills"])
                and ."$schema" == "https://schemas.agentskills.io/discovery/0.2.0/schema.json"
                and (.skills | type == "array" and length > 0)
                and ([.skills[].name] == ([.skills[].name] | unique))
                and all(.skills[];
                  keys == ["description", "digest", "name", "type", "url"]
                  and (.name | test("^[a-z0-9]+(-[a-z0-9]+)*$") and length <= 64)
                  and (.description | type == "string" and length > 0 and length <= 1024)
                  and (.digest | test("^sha256:[0-9a-f]{64}$"))
                  and (if .type == "skill-md" then .url == "/.well-known/agent-skills/\(.name)/SKILL.md"
                       elif .type == "archive" then .url == "/.well-known/agent-skills/\(.name).zip"
                       else false end))
              ' "$index" > /dev/null || fail "index.json does not have the RFC v0.2.0 shape"

              jq -r '.skills[] | "\(.digest | ltrimstr("sha256:"))  \(.url | ltrimstr("/"))"' "$index" > digests
              (cd "$site" && sha256sum --check --quiet) < digests 2>&1 || fail "a digest does not match its file"
              (cd "$site" && find .well-known/agent-skills -type f ! -name index.json | sed 's|^\./||' | LC_ALL=C sort) > files
              cut -d' ' -f3 digests | LC_ALL=C sort > urls
              diff -u --label "published files" --label "index urls" files urls || fail "published files and index urls differ"

              ls -d "$skills"/*/.apm/skills/*/ | xargs -n1 basename | LC_ALL=C sort > first-party
              jq -r '.skills[].name' "$index" | LC_ALL=C sort > indexed
              diff -u --label "first-party skill directories" --label "index names" first-party indexed ||
                fail "the index names other skills than the first-party directories"
              jq -r '.remote | keys[]' "$composed" | LC_ALL=C sort > remote
              remote_indexed=$(comm -12 remote indexed)
              [ -z "$remote_indexed" ] || fail "remote skills in the index: $remote_indexed"

              while read -r name type; do
                dir=$(echo "$skills"/*/.apm/skills/"$name")
                [ -d "$dir" ] || continue
                count=$(find "$dir" -type f | wc -l)
                case "$type:$count" in
                  skill-md:1) ;;
                  archive:1 | skill-md:*) fail "$name is $type but its directory holds $count files" ;;
                  archive:*)
                    mkdir -p "unpacked/$name"
                    unzip -q "$published/$name.zip" -d "unpacked/$name"
                    diff -r "$dir" "unpacked/$name" > /dev/null || fail "$name.zip does not unpack to its directory"
                    ;;
                esac
              done < <(jq -r '.skills[] | "\(.name) \(.type)"' "$index")

              cp -R "$skills" sources
              chmod -R u+w sources
              find sources -exec touch -d '2001-02-03 04:05:06' {} +
              (umask 077 && python3 ${index.generator} sources regenerated)
              diff -r "$published" regenerated > /dev/null || fail "a second generator run wrote other bytes"

              [ "$status" -eq 0 ] || exit 1

              grep -qF 'https://infra.cameronraysmith.net/.well-known/agent-skills/index.json' "$site/llms.txt" ||
                fail "llms.txt does not name the index"
              grep -qF '/.well-known/agent-skills/index.json' "$site/robots.txt" ||
                fail "robots.txt does not name the index"

              # The CLI fetches every artifact at once and silently drops a
              # skill whose fetch fails; behind http.server's default listen
              # backlog of 5 it listed 103 of 125, so the backlog is raised.
              port=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
              python3 -c '
              import functools, http.server, sys
              class Server(http.server.ThreadingHTTPServer):
                  request_queue_size = 1024
              handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=sys.argv[1])
              Server(("127.0.0.1", int(sys.argv[2])), handler).serve_forever()
              ' "$site" "$port" 2> server.log &
              server=$!
              trap 'kill $server' EXIT
              for _ in $(seq 50); do
                python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:$port/.well-known/agent-skills/index.json')" 2> /dev/null && break
                sleep 0.2
              done
              base="http://127.0.0.1:$port"
              mkdir proj

              (cd proj && skills add "$base" --list) > list.log 2>&1 || { cat list.log; exit 1; }
              sed -n 's/^│    \([^ ]*\)$/\1/p' list.log | LC_ALL=C sort > listed
              if ! diff -u --label "index names" --label "listed by skills" indexed listed; then
                cat list.log
                fail "skills lists other skills than the index"
              fi

              archive=$(jq -r '[.skills[] | select(.type == "archive")][0].name' "$index")
              single=$(jq -r '[.skills[] | select(.type == "skill-md")][0].name' "$index")
              (cd proj && skills add "$base" --skill "$archive" "$single" -a codex -y) > add.log 2>&1 || { cat add.log; exit 1; }
              for name in "$archive" "$single"; do
                diff -r "$(echo "$skills"/*/.apm/skills/"$name")" "proj/.agents/skills/$name" ||
                  fail "--skill $name did not install its directory unchanged"
                want=$(jq -r --arg n "$name" '.skills[] | select(.name == $n) | .digest' "$index")
                got=$(jq -r --arg n "$name" '.skills[$n].wellKnownDigest // empty' proj/skills-lock.json)
                [ "$got" = "$want" ] || fail "skills-lock.json records $name as '$got', the index as $want"
              done
              [ "$status" -eq 0 ] || { cat add.log; exit 1; }
              echo "listed $(wc -l < listed) skills; installed $archive (archive) and $single (skill-md) unchanged" | tee "$out"
            '';
      };
    };
}
