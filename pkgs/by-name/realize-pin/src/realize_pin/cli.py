"""Command line: `realize-pin <package> <version>`, run in the repository root."""

from __future__ import annotations

import argparse
import sys
import time
from collections.abc import Callable, Sequence
from pathlib import Path

from realize_pin.adapters import ComposeSkillHasher, GitCli, NixCli, NixUpdateHasher, TreeFiles, UrllibHttp
from realize_pin.capabilities import Capabilities
from realize_pin.model import PACKAGE_NAME, VERSION
from realize_pin.realize import Deadline, realize


def real_capabilities(root: Path) -> Capabilities:
    return Capabilities(
        http=UrllibHttp(),
        nix=NixCli(root),
        hasher=NixUpdateHasher(root),
        skills=ComposeSkillHasher(root),
        git=GitCli(root),
        files=TreeFiles(root),
    )


def main(
    argv: Sequence[str] | None = None,
    capabilities: Callable[[Path], Capabilities] = real_capabilities,
    clock: Callable[[], float] = time.monotonic,
) -> int:
    """Run the realizer in the current directory; tests pass their own capabilities and clock."""
    parser = argparse.ArgumentParser(
        prog="realize-pin",
        usage="realize-pin <package> <version>",
        description=(
            "Rewrite pkgs/by-name/<package>/pin.json and its typed companion files for <version>, "
            "or leave every file as it was and exit non-zero."
        ),
    )
    _ = parser.add_argument("package", help="package attribute name with a pin.json")
    _ = parser.add_argument("version", help="the version to realize, as the dependency updater names it")
    args = parser.parse_args(argv)
    package: str = args.package
    version: str = args.version
    if PACKAGE_NAME.fullmatch(package) is None:
        parser.error(f"package {package!r} is not [a-z0-9][a-z0-9-]*")
    if VERSION.fullmatch(version) is None:
        parser.error(f"version {version!r} is not [0-9A-Za-z][0-9A-Za-z.+_-]*")
    result = realize(package, version, capabilities(Path.cwd()), Deadline.start(clock))
    if result.is_error():
        print(result.error.render(), file=sys.stderr)
        return 1
    changed = result.ok.changed
    summary = ", ".join(changed) if changed else "no file changed"
    print(f"realize-pin: {package} {version}: {summary}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
