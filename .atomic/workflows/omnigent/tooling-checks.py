import importlib.util
import pathlib
import re
import tempfile


def load(name):
    spec = importlib.util.spec_from_file_location(name, pathlib.Path(__file__).with_name(name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def rejected(action):
    try:
        action()
    except AssertionError:
        return
    raise AssertionError("Omission control unexpectedly passed")


def main():
    structural = load("runtime-contract-checks")
    resolution = load("tooling-resolution")
    root = pathlib.Path(__file__).resolve().parents[3]
    shared_path = pathlib.Path("modules/home/ai/omnigent/runtime-packages.nix")
    original = (root / shared_path).read_text()
    baseline = re.sub(r"\[\s*pkgs\.bubblewrap(?:\s+pkgs\.(?:procps|lsof))*\s*\]", "[ pkgs.bubblewrap ]", original).replace("      pkgs.gh\n", "")
    upgraded = baseline.replace("      pkgs.nix\n", "      pkgs.nix\n      pkgs.gh\n").replace("[ pkgs.bubblewrap ]", "[ pkgs.bubblewrap pkgs.procps pkgs.lsof ]")
    with tempfile.TemporaryDirectory() as directory:
        candidate = pathlib.Path(directory)
        for relative in [shared_path, pathlib.Path("modules/nixos/omnigent-host.nix"), pathlib.Path("modules/darwin/omnigent-host.nix")]:
            target = candidate / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text((root / relative).read_text())
        target = candidate / shared_path
        target.write_text(baseline)
        structural.check(candidate)
        rejected(lambda: structural.check(candidate, tooling=True))
        target.write_text(upgraded)
        structural.check(candidate, tooling=True)
        rejected(lambda: structural.check(candidate))
        for label, contents in [
            ("gh-only", upgraded.replace(" pkgs.procps", "").replace(" pkgs.lsof", "")),
            ("cleanup-only", upgraded.replace("      pkgs.gh\n", "")),
            ("missing-procps", upgraded.replace(" pkgs.procps", "")),
            ("missing-lsof", upgraded.replace(" pkgs.lsof", "")),
        ]:
            target.write_text(contents)
            rejected(lambda: structural.check(candidate, tooling=True))
            print(f"PASS structural omission rejected: {label}")
        bins = candidate / "bin"
        bins.mkdir()
        names = ["gh", "ps", "lsof"]
        for name in names:
            executable = bins / name
            executable.write_text("#!/bin/sh\nexit 0\n")
            executable.chmod(0o700)
        binding = {"path": str(bins), "expected": {name: str(bins / name) for name in names}}
        resolution.resolve_local(binding, names)
        for name in names:
            executable = bins / name
            executable.chmod(0o600)
            rejected(lambda: resolution.resolve_local(binding, names))
            if name == "lsof":
                rejected(lambda: resolution.resolve_local({"path": str(bins), "expected": {"lsof": str(executable)}}, ["lsof"]))
            executable.chmod(0o700)
            print(f"PASS executable omission rejected: {name}")
    print("runtime-tooling-controls-ok")


if __name__ == "__main__":
    main()
