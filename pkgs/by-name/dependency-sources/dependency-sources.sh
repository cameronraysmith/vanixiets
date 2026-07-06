#!/usr/bin/env bash
# shellcheck shell=bash

usage() {
  cat <<'USAGE'
dependency-sources - extract normalized git-forge source URLs of a workspace's
declared first-order dependencies, one per line, for feeding to `ghq get`.

Usage:
  dependency-sources --language <rust|python|typescript|nix> [options]

Options:
  --path <dir>       Workspace root to inspect (default: ".").
  --language <lang>  REQUIRED. One of: rust, python, typescript, nix.
  --output <file>    Write URLs to <file> (default: stdout).
  --runtime-only     Narrow to runtime dependencies only (default: off; the
                     default emits every declared dependency).
  -h, --help         Show this help and exit.

Dependency sets:
  default (everything declared)
    rust        all [dependencies] kinds (normal, dev, build)
    python      [project.dependencies] + [project.optional-dependencies]
                + [dependency-groups]
    typescript  dependencies + devDependencies + optionalDependencies
                + peerDependencies
    nix         all direct flake inputs
  --runtime-only (narrowed)
    rust        [dependencies] with kind == null
    python      [project.dependencies] only
    typescript  dependencies only
    nix         all direct flake inputs (nix has no runtime/dev distinction)

Resolution model (offline-first):
  rust        `cargo metadata --offline`; cargo resolves from the ambient PATH.
  python      python3 stdlib over pyproject.toml plus the project's .venv
              metadata, falling back to the PyPI JSON API only when online.
  typescript  jq over package.json plus a node_modules walk. This build has no
              npm fallback (nodejs is intentionally not vendored), so packages
              absent from node_modules stay unresolved; run your install step
              first.
  nix         jq over flake.lock; nix from the ambient PATH is used only for the
              rare metadata fallback when flake.lock is absent.

Output is deduplicated, sorted, and normalized to https://<host>/<owner>/<repo>.
Nixpkgs channel tarballs and non-forge/path/indirect inputs are skipped.
USAGE
}

extract_rust() {
  local path="${1%/}" ronly="$2" onlyjson
  if [ "$ronly" = "1" ]; then onlyjson=true; else onlyjson=false; fi
  cargo metadata --format-version 1 --offline --manifest-path "${path}/Cargo.toml" 2>/dev/null \
    | jq -r --argjson ronly "$onlyjson" '
        def forgey: test("github|gitlab|bitbucket|codeberg|gitea|sr[.]ht");
        def norm: ( sub("^http://";"https://")
          | sub("/(tree|blob)/.*$";"") | sub("/-/.*$";"")
          | rtrimstr(".git") | rtrimstr("/") );
        (.workspace_members) as $wm
        | (reduce .packages[] as $p ({};
            .[$p.name] = ( ($p.repository // "")
                           | if . != "" then .
                             else (($p.homepage // "") | if forgey then . else "" end) end ))) as $repo
        | .packages[] | select(.id as $i | ($wm|index($i)))
        | .dependencies[]
        | (if $ronly then select(.kind == null) else . end)
        | ($repo[.name] // "") | select(. != "") | norm
      ' | LC_ALL=C sort -u
}

extract_python() {
  local path="$1" ronly="$2"
  python3 - "$path" "$ronly" <<'PY'
import sys, os, glob, tomllib, re, json, urllib.request, urllib.error
from urllib.parse import urlparse

NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*")
FORGE_HOSTS = {"github.com", "gitlab.com", "codeberg.org", "bitbucket.org",
               "git.sr.ht", "gitea.com", "gitlab.freedesktop.org"}

def bare_name(dep):
    dep = dep.strip()
    if not dep or dep.startswith("#"):
        return None
    m = NAME_RE.match(dep)
    return m.group(0).lower() if m else None

def load(path):
    with open(path, "rb") as f:
        return tomllib.load(f)

def member_manifests(root):
    pp = os.path.join(root, "pyproject.toml")
    manifests = []
    if os.path.isfile(pp):
        data = load(pp)
        ws = data.get("tool", {}).get("uv", {}).get("workspace")
        if ws:
            if "project" in data:
                manifests.append(pp)
            excl = set()
            for g in ws.get("exclude", []):
                excl.update(glob.glob(os.path.join(root, g)))
            for g in ws.get("members", []):
                for d in glob.glob(os.path.join(root, g)):
                    if d in excl:
                        continue
                    mp = os.path.join(d, "pyproject.toml")
                    if os.path.isfile(mp):
                        manifests.append(mp)
            return manifests
        return [pp]
    for pat in ("packages/*/pyproject.toml", "*/pyproject.toml"):
        for mp in glob.glob(os.path.join(root, pat)):
            if any(seg in mp for seg in (".venv", "node_modules", ".pixi", "external-references")):
                continue
            manifests.append(mp)
    return sorted(set(manifests))

def internal_names(manifests):
    names = set()
    for mp in manifests:
        n = load(mp).get("project", {}).get("name")
        if n:
            names.add(n.lower())
    return names

def dep_specifiers(data, runtime_only):
    proj = data.get("project", {})
    yield from (proj.get("dependencies", []) or [])
    if runtime_only:
        return
    for extra in (proj.get("optional-dependencies", {}) or {}).values():
        yield from (extra or [])
    for group in (data.get("dependency-groups", {}) or {}).values():
        yield from (group or [])

def collect(manifests, internal, runtime_only):
    names, git_urls = set(), set()
    for mp in manifests:
        d = load(mp)
        sources = d.get("tool", {}).get("uv", {}).get("sources", {})
        for dep in dep_specifiers(d, runtime_only):
            if not isinstance(dep, str):
                continue
            n = bare_name(dep)
            if not n:
                continue
            src = sources.get(n)
            if isinstance(src, dict):
                if "git" in src:
                    git_urls.add(src["git"]); continue
                if "path" in src or src.get("workspace"):
                    continue
            if n in internal:
                continue
            names.add(n)
    return names, git_urls

def normalize(url):
    url = url.strip()
    if url.startswith("git+"):
        url = url[4:]
    p = urlparse(url)
    host = (p.hostname or "").lower()
    if host not in FORGE_HOSTS:
        return None
    segs = [s for s in p.path.split("/") if s]
    if len(segs) < 2:
        return None
    owner, repo = segs[0], segs[1]
    if repo.endswith(".git"):
        repo = repo[:-4]
    return f"https://{host}/{owner}/{repo}"

def rank_key(key):
    return 0 if key.strip().lower() in ("repository", "source", "source code", "code") else 1

def add_venv_paths(root, manifests):
    for r in [root] + [os.path.dirname(m) for m in manifests]:
        for sp in glob.glob(os.path.join(r, ".venv/lib/python*/site-packages")):
            if sp not in sys.path:
                sys.path.insert(0, sp)

def resolve_offline(name):
    import importlib.metadata as im
    try:
        md = im.metadata(name)
    except im.PackageNotFoundError:
        return None
    cands = []
    for u in (md.get_all("Project-URL") or []):
        parts = u.split(",", 1)
        key, val = (parts[0], parts[1]) if len(parts) == 2 else ("", parts[0])
        cands.append((rank_key(key), val.strip()))
    hp = md.get("Home-page")
    if hp:
        cands.append((2, hp))
    for _, val in sorted(cands, key=lambda c: c[0]):
        nu = normalize(val)
        if nu:
            return nu
    return None

def resolve_pypi(name):
    try:
        with urllib.request.urlopen(f"https://pypi.org/pypi/{name}/json", timeout=10) as r:
            info = json.load(r).get("info", {})
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
        return None
    cands = []
    for key, val in (info.get("project_urls") or {}).items():
        if val:
            cands.append((rank_key(key), val))
    hp = info.get("home_page")
    if hp:
        cands.append((2, hp))
    for _, val in sorted(cands, key=lambda c: c[0]):
        nu = normalize(val)
        if nu:
            return nu
    return None

def main():
    root = os.path.abspath(sys.argv[1])
    runtime_only = len(sys.argv) > 2 and sys.argv[2] == "1"
    manifests = member_manifests(root)
    if not manifests:
        print(f"no pyproject.toml under {root}", file=sys.stderr)
        return 1
    internal = internal_names(manifests)
    names, git_urls = collect(manifests, internal, runtime_only)
    add_venv_paths(root, manifests)
    out = set()
    for g in git_urls:
        nu = normalize(g)
        if nu:
            out.add(nu)
    for n in sorted(names):
        u = resolve_offline(n) or resolve_pypi(n)
        if u:
            out.add(u)
        else:
            print(f"unresolved: {n}", file=sys.stderr)
    for u in sorted(out):
        print(u)
    return 0

sys.exit(main())
PY
}

extract_typescript() {
  local path="${1%/}" ronly="$2"
  local root_pkg="${path}/package.json"
  if [ ! -f "$root_pkg" ]; then
    printf 'extract_typescript: no package.json at %s\n' "$path" >&2
    return 1
  fi

  local sections
  if [ "$ronly" = "1" ]; then
    sections='[(.dependencies // {})]'
  else
    sections='[(.dependencies // {}), (.devDependencies // {}), (.optionalDependencies // {}), (.peerDependencies // {})]'
  fi

  local -a manifests=("$root_pkg")
  local -a search_dirs=("$path")

  local glob_pat member_pkg
  while IFS= read -r glob_pat; do
    if [ -z "$glob_pat" ]; then continue; fi
    # shellcheck disable=SC2086  # word-splitting the workspace glob is intended
    for member_pkg in "$path"/$glob_pat/package.json; do
      if [ ! -f "$member_pkg" ]; then continue; fi
      manifests+=("$member_pkg")
      search_dirs+=("${member_pkg%/package.json}")
    done
  done < <(jq -r 'if (.workspaces|type)=="array" then .workspaces[] elif (.workspaces|type)=="object" then (.workspaces.packages[]?) else empty end' "$root_pkg" 2>/dev/null)

  local -a internal_names=()
  local m
  for m in "${manifests[@]}"; do
    internal_names+=("$(jq -r '.name // empty' "$m" 2>/dev/null || true)")
  done

  local names
  names="$(for m in "${manifests[@]}"; do
    jq -r "${sections} | add // {} | keys[]" "$m" 2>/dev/null
  done | LC_ALL=C sort -u)" || names=""

  local jq_defs
  jq_defs="$(
    cat <<'JQEOF'
def forgey: test("github|gitlab|bitbucket|codeberg|gitea|sr[.]ht");
def pick:
  ((.repository // null) | if type=="object" then (.url // "") else (. // "") end) as $r
  | (.homepage // "") as $h
  | if ($r|type)=="string" and ($r|length) > 0 then $r
    elif ($h|type)=="string" and ($h|length) > 0 and ($h|forgey) then $h
    else empty end;
def norm:
  ltrimstr("git+") | ltrimstr("ssh://") | ltrimstr("git://")
  | ltrimstr("https://") | ltrimstr("http://") | ltrimstr("git@")
  | (if test("^github:") then "github.com/" + ltrimstr("github:")
     elif test("^gitlab:") then "gitlab.com/" + ltrimstr("gitlab:")
     elif test("^bitbucket:") then "bitbucket.org/" + ltrimstr("bitbucket:")
     elif test("^gist:") then "gist.github.com/" + ltrimstr("gist:")
     else . end)
  | sub("[:]"; "/")
  | split("#")[0] | split("?")[0]
  | split("/")
  | (if (.[0] | test("[.]")) then . else (["github.com"] + .) end)
  | .[0:3] | join("/")
  | rtrimstr("/") | rtrimstr(".git")
  | if (test("[.]") and test("/")) then "https://" + . else empty end;
JQEOF
  )"

  local name manifest url dir i skip walk raw
  {
    while IFS= read -r name; do
      if [ -z "$name" ]; then continue; fi

      skip=0
      for i in "${internal_names[@]}"; do
        if [ "$name" = "$i" ]; then skip=1; break; fi
      done
      if [ "$skip" -eq 1 ]; then continue; fi

      url=""
      for dir in "${search_dirs[@]}"; do
        walk="$dir"
        while :; do
          manifest="${walk}/node_modules/${name}/package.json"
          if [ -f "$manifest" ]; then
            url="$(jq -r "${jq_defs} pick | norm" "$manifest" 2>/dev/null | head -n1)" || url=""
            if [ -n "$url" ]; then break; fi
          fi
          if [ "$walk" = "" ]; then break; fi
          if [ "$walk" = "/" ]; then break; fi
          walk="${walk%/*}"
          if [ -z "$walk" ]; then walk="/"; fi
        done
        if [ -n "$url" ]; then break; fi
      done

      if [ -z "$url" ] && command -v npm >/dev/null 2>&1; then
        raw="$(npm view "$name" repository.url </dev/null 2>/dev/null | head -n1)" || raw=""
        if [ -n "$raw" ]; then
          url="$(printf '%s' "$raw" | jq -Rr "${jq_defs} norm" 2>/dev/null | head -n1)" || url=""
        fi
      fi

      if [ -n "$url" ]; then printf '%s\n' "$url"; fi
    done <<< "$names"
  } | LC_ALL=C sort -u
}

extract_nix() {
  local path="$1"
  local filter
  # shellcheck disable=SC2016  # $n/$o are jq variables, intentionally unexpanded by the shell
  filter='
    .nodes as $n
    | ($n[.root].inputs // {})
    | to_entries[]
    | select(.value | type == "string")
    | ($n[.value].original) as $o
    | select($o != null)
    | (
        if $o.type == "github" then
          "https://" + ($o.host // "github.com") + "/" + $o.owner + "/" + $o.repo
        elif $o.type == "gitlab" then
          "https://" + ($o.host // "gitlab.com") + "/" + $o.owner + "/" + $o.repo
        elif $o.type == "sourcehut" then
          "https://" + ($o.host // "git.sr.ht") + "/" + $o.owner + "/" + $o.repo
        elif $o.type == "git" then
          ($o.url | ltrimstr("git+") | split("?")[0] | rtrimstr("/") | rtrimstr(".git"))
        elif $o.type == "tarball" then
          (if ($o.url | contains("/archive/"))
           then ($o.url | ltrimstr("git+") | split("/archive/")[0])
           else empty end)
        else empty end
      )
    | select(. != null and . != "")
  '

  {
    if [ -f "${path}/flake.lock" ]; then
      jq -r "${filter}" "${path}/flake.lock"
    else
      nix flake metadata --json --no-write-lock-file -- "${path}" \
        | jq '.locks' \
        | jq -r "${filter}"
    fi
  } | LC_ALL=C sort -u
}

path="."
language=""
output=""
runtime_only=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --path=*) path="${1#*=}" ;;
    --language=*) language="${1#*=}" ;;
    --output=*) output="${1#*=}" ;;
    --path | --language | --output)
      opt="$1"
      if [ "$#" -lt 2 ]; then
        printf 'error: %s requires a value\n\n' "$opt" >&2
        usage >&2
        exit 2
      fi
      shift
      case "$opt" in
        --path) path="$1" ;;
        --language) language="$1" ;;
        --output) output="$1" ;;
      esac
      ;;
    --runtime-only) runtime_only=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      printf 'error: unknown option: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      printf 'error: unexpected argument: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

case "$language" in
  rust | python | typescript | nix) ;;
  "")
    printf 'error: --language is required (rust|python|typescript|nix)\n\n' >&2
    usage >&2
    exit 2
    ;;
  *)
    printf 'error: invalid --language: %s (expected rust|python|typescript|nix)\n\n' "$language" >&2
    usage >&2
    exit 2
    ;;
esac

if [ ! -d "$path" ]; then
  printf 'error: --path is not a directory: %s\n' "$path" >&2
  exit 2
fi

result=""
case "$language" in
  rust) result="$(extract_rust "$path" "$runtime_only")" || result="" ;;
  python) result="$(extract_python "$path" "$runtime_only")" || result="" ;;
  typescript) result="$(extract_typescript "$path" "$runtime_only")" || result="" ;;
  nix) result="$(extract_nix "$path")" || result="" ;;
esac

if [ -n "$output" ]; then
  if [ -n "$result" ]; then
    printf '%s\n' "$result" > "$output"
  else
    : > "$output"
  fi
else
  if [ -n "$result" ]; then
    printf '%s\n' "$result"
  fi
fi
