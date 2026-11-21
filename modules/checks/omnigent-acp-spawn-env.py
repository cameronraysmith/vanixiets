"""Observe the environment each rendered ACP agent's program is executed with.

Drives the packaged omnigent's own code path from a worker's real host unit
environment: the runner environment (omnigent.host.connect._build_runner_env),
the generic ACP spawn environment (AcpExecutor._build_spawn_env), then the
agent's rendered argv executed as omnigent executes it (shlex-split, no shell)
under strace, which records the environment of the execve that starts the
agent program, through any wrapper in between.

Atomic's state selectors are present in the host environment in every case, so
a passthrough that forwards them is caught whatever the unit declares.

Usage: omnigent-acp-spawn-env.py CASES_JSON STRACE
"""

import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path

from omnigent.host.connect import _build_runner_env
from omnigent.inner.acp_executor import AcpAgentConfig, AcpExecutor
from omnigent.onboarding.acp_auth import acp_agents

STATE = ("PI_ACP_PI_COMMAND", "PI_CODING_AGENT_DIR")
# The program each rendered row must end up executing.
PROGRAMS = {"Atomic": "pi-acp", "Oh My Pi": "omp"}
EXECVE = re.compile(r'execve\("((?:[^"\\]|\\.)*)", \[.*?\], \[(.*?)\]')
ENTRY = re.compile(r'"((?:[^"\\]|\\.)*)"')


def program_env(argv: list[str], env: dict[str, str], program: str, strace: str, log: Path):
    """Environment of the first execve of ``program``; failed attempts count.

    The argv is started with a PATH search in the child, as
    asyncio.create_subprocess_exec does, so an absent program still shows the
    environment it would have been given.
    """
    launch = [sys.executable, "-I", "-c", "import os, sys; os.execvp(sys.argv[1], sys.argv[1:])"]
    subprocess.run(
        [strace, "-f", "-v", "-s", "65536", "-e", "trace=execve", "-o", str(log), *launch, *argv],
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=60,
    )
    for line in log.read_text().splitlines():
        match = EXECVE.search(line)
        if match and Path(match.group(1)).name == program:
            entries = (e.encode().decode("unicode_escape") for e in ENTRY.findall(match.group(2)))
            return dict(entry.split("=", 1) for entry in entries)
    raise SystemExit(f"{argv!r} never executed {program}:\n{log.read_text()}")


def spawn_env(command: str, passthrough: tuple[str, ...]) -> dict[str, str]:
    executor = AcpExecutor.__new__(AcpExecutor)
    executor._config = AcpAgentConfig(command=command, env_passthrough=passthrough)
    # The launcher spec gives configured ACP agents os_env sandbox none with no
    # env_passthrough (checked by omnigent-worker-linux), so it adds no names.
    executor._os_env = None
    return executor._build_spawn_env()


def main() -> None:
    cases = json.loads(Path(sys.argv[1]).read_text())
    strace = sys.argv[2]
    work = Path(tempfile.mkdtemp())
    failures = []

    def expect(label: str, ok: bool) -> None:
        print(("ok   " if ok else "FAIL ") + label)
        if not ok:
            failures.append(label)

    for case in cases:
        label = case["label"]
        host_env = {k: str(v) for k, v in case["hostEnvironment"].items()}
        home = host_env["HOME"]
        atomic_dir = f"{home}/.atomic/agent"
        host_env.setdefault("PI_ACP_PI_COMMAND", "atomic")
        host_env.setdefault("PI_CODING_AGENT_DIR", atomic_dir)
        config_home = work / label
        (config_home / ".omnigent").mkdir(parents=True)
        os.environ.clear()
        os.environ["HOME"] = str(config_home)
        runner_env = _build_runner_env(
            host_env,
            server_url="https://fixture.invalid",
            runner_id="runner_fixture",
            binding_token="fixture",
            workspace=home,
            parent_pid=1,
        )
        os.environ.clear()
        os.environ.update(runner_env)
        # PATH only locates agent programs; the host's store paths are not built here.
        os.environ["PATH"] = "/nonexistent"

        agents = {entry.name: entry for entry in acp_agents({"acp": case["acp"]})}
        expect(f"{label}: rendered ACP agents {sorted(agents)}", sorted(agents) == sorted(PROGRAMS))
        for name, entry in agents.items():
            argv = shlex.split(entry.command)
            seen = program_env(
                argv,
                spawn_env(entry.command, tuple(entry.env_passthrough)),
                PROGRAMS[name],
                strace,
                work / f"{label}-{name}.strace",
            )
            if name == "Atomic":
                expect(f"{label}: Atomic PI_ACP_PI_COMMAND=atomic", seen.get("PI_ACP_PI_COMMAND") == "atomic")
                expect(
                    f"{label}: Atomic PI_CODING_AGENT_DIR={atomic_dir}",
                    seen.get("PI_CODING_AGENT_DIR") == atomic_dir,
                )
            else:
                for var in STATE:
                    expect(f"{label}: {name} lacks {var} (got {seen.get(var)!r})", var not in seen)
        generic = spawn_env("generic-acp-agent", ())
        for var in STATE:
            expect(f"{label}: a generic ACP child lacks {var}", var not in generic)
    if failures:
        raise SystemExit(f"{len(failures)} failure(s)")


if __name__ == "__main__":
    main()
