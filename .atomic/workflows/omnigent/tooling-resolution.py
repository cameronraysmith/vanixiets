import argparse
import json
import pathlib
import shlex
import shutil
import subprocess


# A version-bound audit cannot discover executable names constructed at runtime.
def resolve_local(binding, names):
    resolved = {name: shutil.which(name, path=binding["path"]) for name in names}
    assert all(resolved.values()), f"Missing executables: {resolved}"
    for name, expected in binding["expected"].items():
        assert resolved[name] == expected, f"{name}: {resolved[name]} != {expected}"
    return resolved


def resolve_remote(binding, names, host):
    script = 'set -eu\nPATH=' + shlex.quote(binding["path"]) + '\nexport PATH\n'
    for name in names:
        script += f'p=$(command -v {shlex.quote(name)})\ntest -x "$p"\nprintf "%s=%s\\n" {shlex.quote(name)} "$p"\n'
    result = subprocess.run(["ssh", f"root@{host}.zt", "/bin/sh -c " + shlex.quote(script)], check=True, text=True, capture_output=True)
    resolved = dict(line.split("=", 1) for line in result.stdout.splitlines())
    for name, expected in binding["expected"].items():
        assert resolved[name] == expected, f"{name}: {resolved[name]} != {expected}"
    return resolved


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binding-expr", required=True)
    parser.add_argument("--host", choices=["magnetite", "pyrite", "stibnite"], required=True)
    parser.add_argument("--server", action="store_true")
    args = parser.parse_args()
    manifest = json.loads(pathlib.Path(__file__).with_name("tooling-manifest.json").read_text())
    binding = json.loads(subprocess.check_output(["nix", "eval", "--json", "--impure", "--expr", args.binding_expr], text=True))
    assert binding["version"] == manifest["version"], "Package changed: renew the upstream PATH audit"
    names = manifest["server" if args.server else "runner"]
    resolved = resolve_local(binding, names) if args.host == "stibnite" else resolve_remote(binding, names, args.host)
    print(json.dumps({"host": args.host, "owner": "server" if args.server else "runner", "version": binding["version"], "path": binding["path"], "packageOutputs": binding["outputs"], "resolved": resolved}, sort_keys=True))
    for omitted, executable in binding["expected"].items():
        mutant = {**binding, "path": ":".join(part for part in binding["path"].split(":") if part != str(pathlib.Path(executable).parent))}
        try:
            if args.host == "stibnite":
                resolve_local(mutant, names)
            else:
                resolve_remote(mutant, names, args.host)
        except AssertionError:
            pass
        except subprocess.CalledProcessError as error:
            if error.returncode != 1:
                raise
        else:
            raise AssertionError(f"Omission control accepted missing {omitted}")
        print(f"omission-rejected {args.host} {'server' if args.server else 'runner'} {omitted}")
    print("runtime-tooling-resolution-ok")


if __name__ == "__main__":
    main()
