from __future__ import annotations

import base64
import importlib.util
import json
import os
import pathlib
import re
import secrets
import shlex
import shutil
import struct
import subprocess
import sys
from unittest.mock import patch


def mock(tool: str) -> None:
    arguments = sys.argv[2:]
    marker = pathlib.Path(os.environ["FIXTURE_ARGV"])
    with marker.open("a") as stream:
        stream.write(json.dumps([tool, *arguments]) + "\n")
    if tool == "gh":
        token = os.environ.get("GH_TOKEN")
        assert token
        if arguments == ["api", "user"]:
            print(
                json.dumps({"login": os.environ.get("FIXTURE_GITHUB", "fixture-human")})
            )
        elif arguments == ["auth", "git-credential", "get"]:
            sys.stdin.read()
            print("username=x-access-token\npassword=" + token + "\n")
        else:
            raise AssertionError("unexpected GitHub arguments")


def prepare_linear(root: pathlib.Path) -> None:
    """Bind the resolver to vendored lock versions without optional dev binaries."""
    config_path = root / "deno.json"
    config = json.loads(config_path.read_text())
    lock = json.loads((root / "deno.lock").read_text())
    imports = {}

    def exports(alias: str, specifier: str, version: str) -> None:
        package = specifier.removeprefix("jsr:").rsplit("@", 1)[0]
        directory = root / "vendor/jsr.io" / package / version
        metadata = directory.with_name(version + "_meta.json")
        if metadata.exists():
            for export, target in json.loads(metadata.read_text())["exports"].items():
                imports[alias + export[1:]] = str(directory / target)

    for specifier, version in lock["specifiers"].items():
        if specifier.startswith("jsr:@std/"):
            exports(specifier, specifier, version)
    for alias, specifier in config["imports"].items():
        if alias in ("@std/toml", "@std/path", "@std/fs", "@std/fmt", "@std/dotenv"):
            version = lock["specifiers"][specifier.replace("@^0.", "@~0.")]
            exports(alias, specifier, version)
        elif alias in ("graphql", "graphql-request", "valibot"):
            imports[alias] = specifier
    config.update(imports=imports, vendor=False, nodeModulesDir="none")
    config_path.unlink()
    config_path.write_text(json.dumps(config))


def module(path: str, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


def private_file(path: pathlib.Path, value: bytes, mode: int = 0o400) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        path.chmod(0o600)
    path.write_bytes(value)
    path.chmod(mode)


def signing_key(path: pathlib.Path) -> None:
    seed = bytes.fromhex(
        "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
    )
    public = bytes.fromhex(
        "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
    )
    string = lambda value: struct.pack(">I", len(value)) + value
    public_wire = string(b"ssh-ed25519") + string(public)
    private = (
        struct.pack(">II", 1, 1)
        + string(b"ssh-ed25519")
        + string(public)
        + string(seed + public)
        + string(b"synthetic fixture")
    )
    private += bytes(range(1, 9 - len(private) % 8))
    wire = (
        b"openssh-key-v1\0"
        + string(b"none")
        + string(b"none")
        + string(b"")
        + struct.pack(">I", 1)
        + string(public_wire)
        + string(private)
    )
    encoded = base64.b64encode(wire).decode()
    pem = (
        "-----BEGIN OPENSSH PRIVATE KEY-----\n"
        + "\n".join(encoded[i : i + 70] for i in range(0, len(encoded), 70))
        + "\n-----END OPENSSH PRIVATE KEY-----\n"
    )
    private_file(path, pem.encode())


def generated_files(paths: list[str]):
    visited = set()
    for name in paths:
        path = pathlib.Path(name)
        roots = (
            [
                path / "activate",
                path / "home-files",
                path / "home-path/etc/profile.d/hm-session-vars.sh",
            ]
            if path.is_dir()
            else [path]
        )
        for root in roots:
            if root.is_file():
                yield root
                continue
            for directory, directories, files in os.walk(root, followlinks=True):
                resolved = pathlib.Path(directory).resolve()
                if resolved in visited:
                    directories.clear()
                    continue
                visited.add(resolved)
                for file in files:
                    candidate = pathlib.Path(directory) / file
                    if candidate.is_file():
                        yield candidate


def disclosed(data: bytes, sentinels: tuple[bytes, ...]) -> bool:
    return any(sentinel in data for sentinel in sentinels)


def audit_artifacts(artifact: dict, runtime_sentinel: str) -> None:
    sentinels = (
        runtime_sentinel.encode(),
        pathlib.Path(artifact["evaluationMaterial"]).read_bytes(),
    )
    derivations = [pathlib.Path(path) for path in artifact["derivationRoots"]]
    assert derivations, "empty direct-fixture derivation audit"
    for path in derivations:
        assert not disclosed(path.read_bytes(), sentinels), (
            "derivation credential disclosure in " + str(path)
        )
    settings = list(generated_files(artifact["generatedArtifacts"]))
    assert settings, "empty generated-settings audit"
    for path in settings:
        assert not disclosed(path.read_bytes(), sentinels), (
            "credential disclosure in " + str(path)
        )
    assert any(
        disclosed(path.read_bytes(), sentinels)
        for path in generated_files([artifact["leakingGeneration"]])
    ), "evaluation-time settings leak control did not fail"
    print(
        f"credential disclosure audit: {len(derivations)} derivations, {len(settings)} generated files"
    )


def main() -> None:
    artifact = json.loads(pathlib.Path(sys.argv[1]).read_text())
    root = pathlib.Path(artifact["root"])
    root.mkdir(mode=0o700)
    captured = []
    sentinel = secrets.token_urlsafe(48)
    try:
        home = root / "home"
        home.mkdir(mode=0o700)
        generation = pathlib.Path(artifact["generation"])
        verify = generation / "home-path/bin/omnigent-worker-verify"
        argv = shlex.split(
            next(
                line
                for line in verify.read_text().splitlines()
                if line.startswith("exec ")
            )
        )
        policy_path = pathlib.Path(argv[3])
        policy = json.loads(policy_path.read_text())
        assert policy["home"] == str(home)
        for path in policy["requiredFiles"]:
            private_file(pathlib.Path(path), sentinel.encode())
        signing_key(pathlib.Path(policy["signingKey"]))
        grant = policy["linearApiKeys"]["personal"]
        assert set(policy["linearApiKeys"]) == {"personal"}
        for field, value in (
            ("workspace", "fixture"),
            ("workspaceId", "workspace-id"),
            ("viewerEmail", "fixture@example.invalid"),
        ):
            private_file(pathlib.Path(grant[field]), value.encode())
        private_file(
            pathlib.Path(policy["linearCredentials"]),
            artifact["linearTemplate"]
            .replace(artifact["linearPlaceholders"]["key"], sentinel)
            .replace(artifact["linearPlaceholders"]["workspace"], "fixture")
            .encode(),
        )
        oauth = {
            ".atomic/agent/auth.json": b'{"fixture":"refreshed-atomic"}',
            ".pi/agent/auth.json": b'{"fixture":"refreshed-native-pi"}',
            ".omp/agent/agent.db": b"refreshed-omp-independent-state",
            ".codex/auth.json": b'{"fixture":"refreshed-codex"}',
            ".omnigent/auth_tokens.json": json.dumps(
                {
                    policy["serverUrl"]: {
                        "token": sentinel,
                        "user_id": "fixture@example.invalid",
                        "refresh_token": "tool-owned-refresh",
                    }
                }
            ).encode(),
        }
        for relative, value in oauth.items():
            private_file(home / relative, value, 0o600)
        mocks = root / "mocks"
        mocks.mkdir()
        (mocks / "sitecustomize.py").write_text("""import io, json, os, urllib.request
class MockOpener:
    def open(self, request, timeout):
        assert request.full_url == "https://fixture.invalid/v1/me"
        assert request.get_header("Authorization").startswith("Bearer ")
        return io.BytesIO(json.dumps({"user_id": os.environ.get("FIXTURE_OMNIGENT", "fixture@example.invalid"), "is_admin": False}).encode())
urllib.request.build_opener = lambda *handlers: MockOpener()
import subprocess
real_run, real_exec = subprocess.run, os.execve
def run(arguments, **kwargs):
    if arguments[:2] == ["/usr/bin/security", "find-generic-password"]:
        return subprocess.CompletedProcess(arguments, int(os.environ.get("FIXTURE_KEYCHAIN", "44")))
    return real_run(arguments, **kwargs)
def execute(executable, arguments, environment):
    if executable.endswith("/bin/claude"):
        assert environment.get("CLAUDE_CODE_OAUTH_TOKEN")
        assert "GH_TOKEN" not in environment
        with open(os.environ["FIXTURE_ARGV"], "a") as stream:
            stream.write(json.dumps(["claude", *arguments[1:]]) + "\\n")
        os._exit(0)
    real_exec(executable, arguments, environment)
subprocess.run, os.execve = run, execute
""")
        environment = dict(
            os.environ,
            HOME=str(home),
            XDG_CONFIG_HOME=str(home / ".config"),
            PYTHONPATH=str(mocks),
            FIXTURE_ARGV=str(root / "argv.jsonl"),
            FIXTURE_LINEAR_GRANT_PATH=grant["path"],
        )
        for key in (
            "GH_TOKEN",
            "GITHUB_TOKEN",
            "LINEAR_API_KEY",
            "LINEAR_WORKSPACE",
            "SSH_AUTH_SOCK",
            "SSH_AGENT_PID",
        ):
            environment.pop(key, None)

        def run(arguments, *, success=True, env=None, data=None, cwd=None, unset=()):
            command_environment = environment | (env or {})
            for name in unset:
                command_environment.pop(name, None)
            result = subprocess.run(
                [str(arg) for arg in arguments],
                input=data,
                env=command_environment,
                cwd=cwd or root,
                capture_output=True,
                check=False,
            )
            if data is None or b"protocol=https" not in data:
                captured.extend((result.stdout, result.stderr))
            assert sentinel.encode() not in result.stderr, "credential reached stderr"
            assert (result.returncode == 0) == success, (
                arguments[0],
                result.returncode,
            )
            return result

        run([verify])
        runtime = module(artifact["consumerSource"], "credentials")
        with patch.dict(
            os.environ,
            environment
            | {"LINEAR_GRAPHQL_ENDPOINT": "https://unapproved.invalid/graphql"},
        ):
            assert "LINEAR_GRAPHQL_ENDPOINT" not in runtime.linear_environment(policy)
        try:
            runtime.material(policy["githubToken"], os.getuid() + 1)
        except runtime.CredentialError:
            pass
        else:
            raise AssertionError("accepted wrong credential owner")
        alternate = root / "alternate-signing-key"
        run(
            [
                policy["executables"]["ssh-keygen"],
                "-t",
                "ed25519",
                "-N",
                "",
                "-f",
                alternate,
            ]
        )
        selected_signer = pathlib.Path(policy["signingKey"])
        original_signer = selected_signer.read_bytes()
        private_file(selected_signer, alternate.read_bytes())
        run([verify], success=False)
        private_file(selected_signer, original_signer)
        run([verify])
        for selector in (
            "FIXTURE_GITHUB",
            "FIXTURE_LINEAR_VIEWER",
            "FIXTURE_LINEAR_WORKSPACE",
            "FIXTURE_OMNIGENT",
        ):
            run([verify], success=False, env={selector: "other-person-or-workspace"})
        gh = generation / "home-path/bin/gh"
        run([gh, "api", "user"])
        run([gh, "api", "user"], env={"GH_TOKEN": sentinel})
        run(
            [gh, "api", "user"],
            success=False,
            env={"GH_TOKEN": "unapproved-ambient-grant"},
        )
        github_path = pathlib.Path(policy["githubToken"])
        original = github_path.read_bytes()
        github_path.unlink()
        run([gh, "api", "user"], success=False)
        private_file(github_path, b"")
        run([gh, "api", "user"], success=False)
        private_file(github_path, original, 0o644)
        run([gh, "api", "user"], success=False)
        github_path.chmod(0o400)
        assert "GH_TOKEN" not in environment

        git_configs = [
            p
            for p in (generation / "home-files").rglob("*")
            if str(p).endswith(("/git/config", "/.gitconfig"))
        ]
        assert len(git_configs) == 1
        git_config = git_configs[0]
        query = lambda key: (
            run([artifact["git"], "config", "--file", git_config, "--get", key])
            .stdout.decode()
            .strip()
        )
        helper = query("credential.https://github.com.helper")
        helper_argv = shlex.split(helper)
        assert helper_argv[0].startswith("/") and helper_argv[1:] == [
            "auth",
            "git-credential",
        ]
        assert pathlib.Path(helper_argv[0]).resolve() == gh.resolve()
        assert query("user.signingkey") == policy["signingKey"]
        assert query("user.email") == "fixture@example.invalid"
        result = run(
            [
                artifact["git"],
                "-c",
                "include.path=" + str(git_config),
                "credential",
                "fill",
            ],
            data=b"protocol=https\nhost=github.com\n\n",
        )
        assert ("password=" + sentinel).encode() in result.stdout
        assert sentinel.encode() not in result.stderr
        run(
            [artifact["mockGh"], "auth", "git-credential", "get"],
            success=False,
            data=b"protocol=https\nhost=github.com\n\n",
        )
        repo = root / "repo"
        run([artifact["git"], "init", repo])
        run(
            [
                artifact["git"],
                "-c",
                "include.path=" + str(git_config),
                "-c",
                "user.name=Fixture",
                "commit",
                "--allow-empty",
                "-m",
                "synthetic signed commit",
            ],
            cwd=repo,
        )
        run(
            [
                artifact["git"],
                "-c",
                "include.path=" + str(git_config),
                "verify-commit",
                "HEAD",
            ],
            cwd=repo,
        )
        wrong_signers = root / "wrong-signers"
        wrong_signers.write_text(
            'other@example.invalid namespaces="git" '
            + policy["expected"]["signingPublicKey"]
            + "\n"
        )
        commit = run([artifact["git"], "cat-file", "commit", "HEAD"], cwd=repo).stdout
        payload, signature = [], []
        in_signature = False
        for line in commit.splitlines(keepends=True):
            if line.startswith(b"gpgsig "):
                signature.append(line[7:])
                in_signature = True
            elif in_signature and line.startswith(b" "):
                signature.append(line[1:])
            else:
                in_signature = False
                payload.append(line)
        signature_file = root / "commit.sig"
        signature_file.write_bytes(b"".join(signature))
        for signers, success in (
            (query("gpg.ssh.allowedSignersFile"), True),
            (wrong_signers, False),
        ):
            run(
                [
                    policy["executables"]["ssh-keygen"],
                    "-Y",
                    "verify",
                    "-I",
                    "fixture@example.invalid",
                    "-n",
                    "git",
                    "-f",
                    signers,
                    "-s",
                    signature_file,
                ],
                data=b"".join(payload),
                success=success,
            )
        linear = generation / "home-path/bin/linear"
        run([linear, "--workspace", "fixture", "api", "query { viewer { email } }"])
        run(
            [linear, "--workspace", "personal", "api", "query { viewer { email } }"],
            success=False,
        )
        for field in ("workspace", "workspaceId", "viewerEmail"):
            path = pathlib.Path(grant[field])
            original_metadata = path.read_bytes()
            private_file(path, b"other-synthetic-identity")
            run([verify], success=False)
            private_file(path, original_metadata)
        workspace_path = pathlib.Path(grant["workspace"])
        workspace_path.unlink()
        run(
            [linear, "--workspace", "fixture", "api", "query { viewer { email } }"],
            success=False,
        )
        private_file(workspace_path, b"fixture")
        run([linear, "api", "query { viewer { email } }"], success=False)
        run(
            [linear, "--workspace", "other", "api", "query { viewer { email } }"],
            success=False,
        )
        run(
            [linear, "--workspace", "fixture", "api", "query { viewer { email } }"],
            success=False,
            env={"LINEAR_API_KEY": sentinel},
        )
        private_file(root / "linear.toml", ('api_key = "' + sentinel + '"').encode())
        run(
            [linear, "--workspace", "fixture", "api", "query { viewer { email } }"],
            success=False,
        )
        (root / "linear.toml").unlink()
        private_file(root / ".env", ("LINEAR_API_KEY=" + sentinel).encode())
        run([linear, "--workspace", "fixture", "api", "query { viewer { email } }"])
        for config_name in (
            ".linear.toml",
            ".config/linear.toml",
            "home/.config/linear/linear.toml",
        ):
            competing = root / config_name
            private_file(competing, ('api_key = "' + sentinel + '"').encode())
            run(
                [linear, "--workspace", "fixture", "api", "query { viewer { email } }"],
                success=False,
            )
            competing.unlink()
        external = root / "external-worktree"
        run([artifact["git"], "init", external])
        external_environment = {
            "GIT_DIR": str(external / ".git"),
            "GIT_WORK_TREE": str(external),
        }
        external_grant = root / "external-grant"
        private_file(external_grant, b"external-grant")
        foreign_config = external / ".config/linear/linear.toml"
        private_file(foreign_config, b'api_key = "external-grant"')
        foreign_environment = {
            "HOME": str(external),
            "LINEAR_IGNORE_ENV_FILE": "1",
            "FIXTURE_LINEAR_GRANT_PATH": str(external_grant),
        }
        for executable, success in ((artifact["mockLinear"], True), (linear, False)):
            run(
                [
                    executable,
                    "--workspace",
                    "fixture",
                    "api",
                    "query { viewer { email } }",
                ],
                env=foreign_environment,
                unset=("XDG_CONFIG_HOME",),
                success=success,
            )
        foreign_config.unlink()
        for config_name in ("linear.toml", ".linear.toml", ".config/linear.toml"):
            competing = external / config_name
            private_file(competing, b'api_key = "external-grant"')
            run(
                [
                    artifact["mockLinear"],
                    "--workspace",
                    "fixture",
                    "api",
                    "query { viewer { email } }",
                ],
                env=external_environment
                | {
                    "LINEAR_IGNORE_ENV_FILE": "1",
                    "FIXTURE_LINEAR_GRANT_PATH": str(external_grant),
                },
            )
            run(
                [linear, "--workspace", "fixture", "api", "query { viewer { email } }"],
                success=False,
                env=external_environment
                | {"FIXTURE_LINEAR_GRANT_PATH": str(external_grant)},
            )
            competing.unlink()
        run(
            [linear, "--workspace", "fixture", "api", "query { viewer { email } }"],
            env=external_environment,
        )
        template_path = pathlib.Path(policy["linearCredentials"])
        template = template_path.read_bytes()
        for invalid in (
            b'default = "fixture"',
            b'default = "fixture"\nfixture = ""',
            b'default = "fixture"\nfixture = "wrong-grant"',
            template + b'\nother = "competing-workspace"',
            template + b'\nfixture = "duplicate-workspace"',
            b'default = "fixture"\nworkspaces = ["fixture"]',
        ):
            private_file(template_path, invalid)
            run(
                [linear, "--workspace", "fixture", "api", "query { viewer { email } }"],
                success=False,
            )
            run([verify], success=False)
        private_file(template_path, template)
        run([linear, "--workspace", "fixture", "api", "query { viewer { email } }"])
        run([verify])
        claude = shutil.which("claude", path=artifact["runtimePath"])
        assert (
            pathlib.Path(claude).resolve()
            == (generation / "home-path/bin/claude").resolve()
        )
        assert (
            pathlib.Path(shutil.which("gh", path=artifact["runtimePath"])).resolve()
            == gh.resolve()
        )
        from omnigent.claude_launcher import resolve_claude_launch
        from omnigent.harnesses.claude_native.main import _preflight_local_tools

        with (
            patch.dict(os.environ, {"PATH": artifact["runtimePath"]}),
            patch(
                "omnigent.harnesses.claude_native.main.validate_claude_hook_interpreter_compatibility"
            ) as check,
        ):
            command, arguments = resolve_claude_launch("claude", ["--settings", "{}"])
            _preflight_local_tools(command)
            check.assert_called_once_with(claude)
        run([claude, *arguments])
        run([claude], success=False, env={"ANTHROPIC_API_KEY": sentinel})
        run([claude, "--settings", '{"apiKeyHelper":"false"}'], success=False)
        private_file(home / ".claude/.credentials.json", b'{"claudeAiOauth":{}}', 0o600)
        run([claude], success=False)
        (home / ".claude/.credentials.json").unlink()
        if sys.platform == "darwin":
            run([claude], success=False, env={"FIXTURE_KEYCHAIN": "0"})
        module(artifact["deliveryFixtures"], "delivery_fixtures").exercise(
            artifact["deliverySource"], root
        )
        launcher = pathlib.Path(artifact["hostLauncher"]).read_text()
        assert " ready" in launcher
        if artifact["systemActivation"] is not None:
            activation = pathlib.Path(artifact["systemActivation"]).read_text()
            assert activation.index("setting up users") < activation.index(
                artifact["installer"]
            )
            assert activation.index(artifact["installer"]) < activation.index(
                "setting up launchd services"
            )
            assert (
                launcher.index(" ready")
                < launcher.index(str(generation) + "/activate")
                < launcher.index("exec ")
            )
            for suffix in (".omnigent", ".omnigent/logs", ".omnigent/logs/host"):
                directory = home / suffix
                directory.mkdir(parents=True, exist_ok=True)
                directory.chmod(0o700)
            uid_command = re.search(r"(/nix/store/[^ \"()]+/bin/id)", launcher).group(1)
            python_command = shlex.split(
                next(
                    line
                    for line in launcher.splitlines()
                    if "delivery.py ready " in line
                )
            )[0]
            executable = root / "launcher.sh"
            events = root / "launch-events"
            body = (
                launcher[: launcher.index("exec ")]
                + 'printf "host\\n" >> "$FIXTURE_EVENTS"\n'
            )
            stubs = f"""{uid_command}() {{
  if test "$*" = '-u omnigent-cameron'; then printf '%s\\n' {os.getuid()};
  else command {uid_command} "$@"; fi
}}
{python_command}() {{
  if test "$1" = {shlex.quote(artifact["deliverySource"])}; then
    printf 'receipt\\n' >> "$FIXTURE_EVENTS"
    return "$FIXTURE_DELIVERY_STATUS"
  fi
  command {python_command} "$@"
}}
{generation}/activate() {{
  printf 'activation\\n' >> "$FIXTURE_EVENTS"
  return "$FIXTURE_ACTIVATION_STATUS"
}}
"""
            for delivery_status, activation_status, expected_events in (
                (1, 0, ["receipt"]),
                (0, 1, ["receipt", "activation"]),
                (0, 0, ["receipt", "activation", "host"]),
            ):
                events.write_text("")
                executable.write_text(stubs + body)
                run(
                    [shlex.split(launcher.splitlines()[0][2:])[0], executable],
                    success=(delivery_status == activation_status == 0),
                    env={
                        "FIXTURE_EVENTS": str(events),
                        "FIXTURE_DELIVERY_STATUS": str(delivery_status),
                        "FIXTURE_ACTIVATION_STATUS": str(activation_status),
                    },
                )
                assert events.read_text().splitlines() == expected_events
            events.write_text("")
            executable.write_text(
                stubs
                + "\n".join(
                    line
                    for line in body.splitlines()
                    if "delivery.py ready " not in line
                )
            )
            run(
                [shlex.split(launcher.splitlines()[0][2:])[0], executable],
                env={
                    "FIXTURE_EVENTS": str(events),
                    "FIXTURE_DELIVERY_STATUS": "1",
                    "FIXTURE_ACTIVATION_STATUS": "0",
                },
            )
            assert events.read_text().splitlines() == ["activation", "host"]
        else:
            run([artifact["hostLauncher"]])
            github_path.unlink()
            run([artifact["hostLauncher"]], success=False)
            private_file(github_path, original)
        activation_text = (generation / "activate").read_text()
        merges = [
            shlex.split(line)[1:]
            for line in activation_text.splitlines()
            if line.startswith(("run ", "$DRY_RUN_CMD "))
            and any(
                name in line
                for name in (
                    "/bin/atomic-merge-settings ",
                    "/bin/omp-merge-config ",
                    "/bin/omnigent-merge-config ",
                )
            )
        ]
        assert len(merges) == 4
        assert all(
            not (generation / "home-files" / relative).exists() for relative in oauth
        )
        older = root / "older-declaration"
        older.write_text("{}")

        def redeploy():
            for declaration in ("current", "current", "rollback"):
                for executable, source, destination in merges:
                    assert destination.startswith(str(home) + "/")
                    run(
                        [
                            executable,
                            older if declaration == "rollback" else source,
                            destination,
                        ]
                    )

        redeploy()
        for relative, value in oauth.items():
            assert (home / relative).read_bytes() == value
        for relative in oauth:
            (home / relative).unlink()
        run([gh, "api", "user"])
        redeploy()
        assert all(not (home / relative).exists() for relative in oauth)
        audit_artifacts(artifact, sentinel)
        settings = [
            pathlib.Path(destination).read_bytes() for _, _, destination in merges
        ]
        argument_log = (root / "argv.jsonl").read_bytes()
        for data in (
            captured
            + settings
            + [
                argument_log,
                policy_path.read_bytes(),
                verify.read_bytes(),
                git_config.read_bytes(),
            ]
        ):
            assert not disclosed(data, (sentinel.encode(),)), (
                "runtime credential disclosure"
            )
        for surface in (
            b"synthetic stdout: ",
            b"synthetic stderr: ",
            b'["synthetic-argv", "',
        ):
            assert disclosed(surface + sentinel.encode(), (sentinel.encode(),))
        print("credential fixtures passed")
    finally:
        shutil.rmtree(root)


if __name__ == "__main__":
    if sys.argv[1] == "mock-gh":
        mock(sys.argv[1].removeprefix("mock-"))
    elif sys.argv[1] == "prepare-linear":
        prepare_linear(pathlib.Path(sys.argv[2]))
    else:
        main()
