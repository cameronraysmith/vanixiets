#!/usr/bin/env bash
set -euo pipefail

cli=$1
# Short socket paths matter on Darwin; keep the CLI's disposable home outside
# the potentially long build directory and never touch a user's live sessions.
test_root=$(mktemp -d /tmp/pw.XXXXXX)
export HOME="$test_root/home"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_CONFIG_HOME="$HOME/.config"
export PLAYWRIGHT_CLI_INSTALLATION_FOR_TEST="$test_root/cli"
export PWTEST_SOCKETS_DIR="$test_root/sockets"
export PLAYWRIGHT_BROWSERS_PATH="$test_root/not-the-cli-browsers"
# Environment overrides outrank project config and can attach a live browser
# or select a user's persistent profile. Keep every MCP override out of fixtures.
for variable in "${!PLAYWRIGHT_MCP_@}"; do
  unset "$variable"
done
unset PWTEST_CLI_GLOBAL_CONFIG PLAYWRIGHT_CLI_SESSION PWDEBUG
mkdir -p "$HOME" "$test_root/project/.playwright"
cd "$test_root/project"

cleanup() {
  status=$?
  if [ "$status" -ne 0 ]; then
    find "$test_root" -name '*.err' -type f -exec cat {} \;
  fi
  "$cli" -s=vanixiets-smoke close >/dev/null 2>&1 || true
  rm -rf "$test_root"
}
trap cleanup EXIT

"$cli" --version | grep -Fx '0.1.21'
"$cli" --help > help.txt
grep -F 'snapshot' help.txt

# A project-relative output directory witnesses that the wrapper keeps cwd
# and that the CLI still discovers its project configuration.
sandbox_option=""
if [ "${PLAYWRIGHT_CLI_TEST_NO_SANDBOX:-0}" = 1 ]; then
  sandbox_option=',"chromiumSandbox":false'
fi
cat > .playwright/cli.config.json <<JSON
{"outputDir":"artifacts","browser":{"launchOptions":{"headless":true$sandbox_option}}}
JSON
"$cli" -s=vanixiets-smoke open about:blank
"$cli" -s=vanixiets-smoke run-code \
  'async page => { await page.setContent("<button onclick=\"this.textContent = &#39;Clicked successfully&#39;\">Click me</button>"); await page.getByRole("button", { name: "Click me" }).click(); }'
"$cli" -s=vanixiets-smoke eval 'document.body.innerText' | tee result.txt
grep -F 'Clicked successfully' result.txt
"$cli" -s=vanixiets-smoke eval \
  'document.querySelector("button").getBoundingClientRect().height > 10' | grep -Fx true
"$cli" -s=vanixiets-smoke snapshot | tee snapshot.txt
grep -F 'button "Clicked successfully"' snapshot.txt
test -d artifacts
"$cli" -s=vanixiets-smoke close
echo 'Playwright CLI browser smoke test passed'
