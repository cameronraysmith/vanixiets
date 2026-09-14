from __future__ import annotations

import json
import os
import re
import stat
import subprocess
import sys
import urllib.request
from pathlib import Path
from typing import Any, NoReturn

import tomllib


class CredentialError(Exception):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise CredentialError(message)


def material(path: str, uid: int) -> bytes:
    with open(path, "rb") as stream:
        info = os.fstat(stream.fileno())
        require(stat.S_ISREG(info.st_mode), "credential is not a regular file")
        require(info.st_uid == uid, "credential owner mismatch")
        require(stat.S_IMODE(info.st_mode) == 0o400, "credential mode mismatch")
        value = stream.read()
    require(bool(value.strip()), "credential is empty")
    return value


def token(path: str) -> str:
    value = material(path, os.getuid()).decode().strip()
    require(not any(c.isspace() for c in value), "credential is not a single token")
    return value


def reject_environment(names: tuple[str, ...]) -> None:
    require(
        not any(name in os.environ for name in names),
        "competing credential environment",
    )


def ready(policy: dict[str, Any]) -> None:
    for path in policy["requiredFiles"]:
        material(path, os.getuid())


def github_environment(policy: dict[str, Any], owner: str) -> dict[str, str]:
    require(owner in policy["githubTokens"], "select a declared OMNIGENT_GH_OWNER")
    approved = token(policy["githubTokens"][owner]["path"])
    for name in (
        "GH_TOKEN",
        "GITHUB_TOKEN",
        "GH_ENTERPRISE_TOKEN",
        "GITHUB_ENTERPRISE_TOKEN",
    ):
        require(
            name not in os.environ or os.environ[name] == approved,
            "competing GitHub credential environment",
        )
    return dict(os.environ, GH_TOKEN=approved)


def github_owner(policy: dict[str, Any], arguments: list[str]) -> str:
    owner = os.environ.get("OMNIGENT_GH_OWNER")
    if owner is None:
        remote = subprocess.run(
            [policy["executables"]["git"], "remote", "get-url", "origin"],
            capture_output=True,
            check=False,
        )
        match = re.fullmatch(
            r"(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)([^/]+)/[^/]+/?",
            remote.stdout.decode().strip(),
        )
        owner = match[1] if remote.returncode == 0 and match else policy["defaultOwner"]
    require(owner in policy["githubTokens"], "select a declared OMNIGENT_GH_OWNER")
    repositories = [os.environ["GH_REPO"]] if "GH_REPO" in os.environ else []
    for index, argument in enumerate(arguments):
        if argument == "--":
            break
        if argument in ("-R", "--repo"):
            require(
                index + 1 < len(arguments),
                "missing repository for OMNIGENT_GH_OWNER check",
            )
            repositories.append(arguments[index + 1])
        elif argument.startswith("--repo="):
            repositories.append(argument.split("=", 1)[1])
        elif argument.startswith("-R"):
            repositories.append(argument[2:].removeprefix("="))
    for repository in repositories:
        match = re.fullmatch(
            r"(?:(?:https://)?github\.com/)?([^/]+)/[^/]+/?", repository
        )
        require(
            match is not None and match[1] == owner,
            "repository differs from selected OMNIGENT_GH_OWNER",
        )
    return owner


def github_credential(policy: dict[str, Any], arguments: list[str]) -> None:
    if arguments != ["get"]:
        return
    request = {}
    for line in sys.stdin:
        line = line.rstrip("\n")
        if not line:
            break
        key, value = line.split("=", 1)
        request[key] = value
    if request.get("protocol") != "https" or request.get("host") != "github.com":
        return
    owner, separator, repository = request.get("path", "").partition("/")
    if not separator or not repository or owner not in policy["githubTokens"]:
        return
    approved = token(policy["githubTokens"][owner]["path"])
    print("username=x-access-token\npassword=" + approved + "\n")


def linear_workspace(arguments: list[str], policy: dict[str, Any]) -> str:
    found = []
    for index, argument in enumerate(arguments):
        if argument in ("--workspace", "-w"):
            require(index + 1 < len(arguments), "missing explicit Linear workspace")
            found.append(arguments[index + 1])
        elif argument.startswith("--workspace="):
            found.append(argument.split("=", 1)[1])
    require(
        len(found) == 1
        and found[0]
        in {token(grant["workspace"]) for grant in policy["linearApiKeys"].values()},
        "select one declared Linear workspace",
    )
    return found[0]


def linear_environment(policy: dict[str, Any]) -> dict[str, str]:
    reject_environment(("LINEAR_API_KEY", "LINEAR_WORKSPACE", "LINEAR_CONFIG"))
    home = Path(policy["home"])
    require(os.environ.get("HOME") == str(home), "foreign Linear consumer home")
    directories = [Path.cwd(), *Path.cwd().parents]
    git_root = (
        subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            check=False,
        )
        .stdout.decode()
        .strip()
    )
    directories.append(Path(git_root))
    candidates = [home / ".config/linear/linear.toml"]
    require(
        os.environ.get("XDG_CONFIG_HOME", str(home / ".config"))
        == str(home / ".config"),
        "foreign Linear configuration home",
    )
    for directory in directories:
        candidates.extend(
            (
                directory / "linear.toml",
                directory / ".linear.toml",
                directory / ".config/linear.toml",
            )
        )
    for path in candidates:
        if path.exists():
            data = tomllib.loads(path.read_text())
            require("api_key" not in data, "competing Linear configuration api_key")
    credentials = tomllib.loads(
        material(policy["linearCredentials"], os.getuid()).decode()
    )
    grants = {
        token(grant["workspace"]): grant for grant in policy["linearApiKeys"].values()
    }
    require(
        len(grants) == len(policy["linearApiKeys"]), "duplicate Linear workspace grants"
    )
    require(
        set(credentials) == {"default", *grants} and credentials["default"] in grants,
        "Linear credential workspaces differ from selected grants",
    )
    for workspace, grant in grants.items():
        require(
            credentials[workspace] == token(grant["path"]),
            "Linear workspace credential differs from delivered grant",
        )
    environment = dict(os.environ, LINEAR_IGNORE_ENV_FILE="1")
    environment.pop("LINEAR_GRAPHQL_ENDPOINT", None)
    return environment


def claude_environment(policy: dict[str, Any], arguments: list[str]) -> dict[str, str]:
    reject_environment(
        (
            "ANTHROPIC_API_KEY",
            "ANTHROPIC_AUTH_TOKEN",
            "CLAUDE_CODE_OAUTH_TOKEN",
            "CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR",
            "CLAUDE_CODE_API_KEY_FILE_DESCRIPTOR",
            "CLAUDE_CODE_USE_BEDROCK",
            "CLAUDE_CODE_USE_VERTEX",
            "CLAUDE_CODE_USE_FOUNDRY",
            "ANTHROPIC_BASE_URL",
            "CLAUDE_CONFIG_DIR",
        )
    )
    inline_settings = []
    for index, argument in enumerate(arguments):
        if argument == "--settings":
            require(index + 1 < len(arguments), "missing Claude settings argument")
            inline_settings.append(arguments[index + 1])
        elif argument.startswith("--settings="):
            inline_settings.append(argument.split("=", 1)[1])
    home = Path(policy["home"])
    config = home / ".claude"
    require(not (config / ".credentials.json").exists(), "competing Claude OAuth file")
    candidates = [config / "settings.json", config / "settings.local.json"]
    for directory in [Path.cwd(), *Path.cwd().parents]:
        candidates.extend(
            (
                directory / ".claude/settings.json",
                directory / ".claude/settings.local.json",
            )
        )
    candidates.append(
        Path("/Library/Application Support/ClaudeCode/managed-settings.json")
        if sys.platform == "darwin"
        else Path("/etc/claude-code/managed-settings.json")
    )
    settings = [json.loads(path.read_text()) for path in candidates if path.exists()]
    for value in inline_settings:
        settings.append(
            json.loads(value)
            if value.lstrip().startswith("{")
            else json.loads(Path(value).read_text())
        )
    for data in settings:
        require("apiKeyHelper" not in data, "competing Claude apiKeyHelper")
        env = data.get("env", {})
        require(
            not any(
                key.startswith(("ANTHROPIC_", "CLAUDE_CODE_OAUTH_", "CLAUDE_CODE_USE_"))
                for key in env
            ),
            "competing Claude settings environment",
        )
    if sys.platform == "darwin":
        result = subprocess.run(
            [
                "/usr/bin/security",
                "find-generic-password",
                "-s",
                "Claude Code-credentials",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        require(
            result.returncode == 44,
            "competing or unavailable Claude Keychain credential source",
        )
    return dict(os.environ, CLAUDE_CODE_OAUTH_TOKEN=token(policy["claudeSetupToken"]))


def command_json(arguments: list[str], environment: dict[str, str]) -> Any:
    result = subprocess.run(
        arguments, env=environment, capture_output=True, check=False
    )
    require(result.returncode == 0, "provider identity query failed")
    return json.loads(result.stdout)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(
        self, req: Any, fp: Any, code: int, msg: str, headers: Any, newurl: str
    ) -> None:
        raise CredentialError("provider identity query redirected")


def omnigent_identity(policy: dict[str, Any]) -> Any:
    path = Path(policy["home"]) / ".omnigent/auth_tokens.json"
    info = path.stat()
    require(
        info.st_uid == os.getuid() and stat.S_IMODE(info.st_mode) & 0o077 == 0,
        "unsafe Omnigent authentication file",
    )
    record = json.loads(path.read_text())[policy["serverUrl"]]
    bearer = record["token"]
    require(isinstance(bearer, str) and bool(bearer), "missing Omnigent bearer")
    request = urllib.request.Request(
        policy["serverUrl"] + "/v1/me", headers={"Authorization": "Bearer " + bearer}
    )
    with urllib.request.build_opener(NoRedirect()).open(
        request, timeout=30
    ) as response:
        return json.load(response)


def verify(policy: dict[str, Any]) -> None:
    ready(policy)
    expected = policy["expected"]
    for owner, grant in policy["githubTokens"].items():
        observed = command_json(
            [policy["executables"]["gh"], "api", "user"],
            github_environment(policy, owner),
        )
        require(
            observed.get("login") == grant["expectedLogin"], "GitHub identity mismatch"
        )
    for grant in policy["linearApiKeys"].values():
        workspace = token(grant["workspace"])
        observed = command_json(
            [
                policy["executables"]["linear"],
                "--workspace",
                workspace,
                "api",
                "query { viewer { email } organization { id urlKey } }",
            ],
            linear_environment(policy),
        )
        data = observed.get("data", observed)
        require(
            data.get("viewer", {}).get("email") == token(grant["viewerEmail"]),
            "Linear viewer mismatch",
        )
        organization = data.get("organization", {})
        require(
            organization.get("id") == token(grant["workspaceId"])
            and organization.get("urlKey") == workspace,
            "Linear workspace mismatch",
        )
    if policy["signingKey"] is not None:
        result = subprocess.run(
            [
                policy["executables"]["ssh-keygen"],
                "-y",
                "-P",
                "",
                "-f",
                policy["signingKey"],
            ],
            capture_output=True,
            check=False,
        )
        require(result.returncode == 0, "signing key is unavailable or encrypted")
        require(
            result.stdout.decode().split()[:2]
            == expected["signingPublicKey"].split()[:2],
            "signing public key mismatch",
        )
    require(
        omnigent_identity(policy).get("user_id") == expected["omnigentEmail"],
        "Omnigent identity mismatch",
    )
    print("worker identity verification passed")


def execute(policy: dict[str, Any], mode: str, arguments: list[str]) -> NoReturn:
    match mode:
        case "gh":
            environment = github_environment(policy, github_owner(policy, arguments))
        case "linear":
            linear_workspace(arguments, policy)
            require(
                "auth" not in arguments,
                "Linear authentication storage is declaratively managed",
            )
            environment = linear_environment(policy)
        case "claude":
            environment = claude_environment(policy, arguments)
        case _:
            raise CredentialError("unknown credential consumer")
    executable = policy["executables"][mode]
    os.execve(executable, [executable, *arguments], environment)


def main() -> None:
    try:
        policy = json.loads(Path(sys.argv[1]).read_text())
        mode = sys.argv[2]
        if mode == "ready":
            ready(policy)
        elif mode == "verify":
            verify(policy)
        elif mode == "gh" and sys.argv[3:5] == ["auth", "git-credential"]:
            github_credential(policy, sys.argv[5:])
        else:
            execute(policy, mode, sys.argv[3:])
    except CredentialError as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1) from None
    except (OSError, ValueError, KeyError, TypeError, IndexError):
        print("worker credential operation failed", file=sys.stderr)
        raise SystemExit(1) from None


if __name__ == "__main__":
    main()
