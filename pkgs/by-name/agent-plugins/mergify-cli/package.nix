{
  fetchFromGitHub,
}:

fetchFromGitHub {
  pname = "agent-plugins-mergify-cli";
  version = "2026.9.16.1";
  owner = "Mergifyio";
  repo = "mergify-cli";
  rev = "e7c1ebbc281361f0b2b7827cf583f57339c97ebc";
  hash = "sha256-i8roSCDYJKtHeb6oDcD1BnUBe0hjLK5v8D5QmxISNVg=";
  passthru.releaseTag = "2026.9.16.1";
}
