## ADDED Requirements

### Requirement: The relay extension is present for every account that runs the agent on a macOS host

On each host of the fleet that runs macOS, every account whose configuration installs the agent SHALL find the relay extension in an extension folder in its private home after each activation, matching the agent release installed for that account, without the person or an agent fetching or installing it by hand.
No host of the fleet that does not run macOS SHALL receive an extension folder.
The discharge of this requirement depends on assumption A69.

#### Scenario: A macOS host is activated for an account that runs the agent

- **WHEN** a configuration that installs the agent for an account is activated on a macOS host of the fleet
- **THEN** that account's private home holds the extension folder, and the relay extension in it reports the same agent release as the agent installed for that account

#### Scenario: A host that does not run macOS is activated

- **WHEN** a configuration is activated on a host of the fleet that does not run macOS
- **THEN** no extension folder is created in any account's private home on that host

### Requirement: Each browser profile loads the relay extension once

A person SHALL need to perform the unpacked load of the extension folder at most once per browser profile on a given host, and the relay extension's extension identity in that browser profile SHALL stay the same across every later agent release, so that the browser profile keeps the extension's settings and permissions.
The discharge of this requirement depends on assumption A67.

#### Scenario: The agent is upgraded after a browser profile loaded the extension

- **WHEN** a configuration carrying a newer agent release is activated on a host where a browser profile has already loaded the extension folder
- **THEN** that browser profile still lists the relay extension under the same extension identity, and the person performs no unpacked load again

### Requirement: The loaded relay extension follows the agent release without being reloaded by hand

After a configuration carrying a newer agent release is activated, the relay extension a browser profile runs SHALL come to report that release once the relay next connects to it while no browser request is using it, without the person reloading the extension or performing the unpacked load again.
The discharge of this requirement depends on assumptions A67, A68 and A69.

#### Scenario: The relay connects after an agent upgrade

- **WHEN** the relay of a newer agent release connects to a browser profile still running the relay extension of the previous release, and no browser request is using that browser profile through the relay
- **THEN** the relay extension in that browser profile reloads and reports the newer release, with no action by the person

### Requirement: An agent drives the person's browser only when a request asks for it

No session SHALL drive tabs of the person's browser by default; a browser request SHALL reach the person's browser through the relay only when that request itself asks for the relay, and every other browser request SHALL use a browser the agent runs for itself.

#### Scenario: A session makes a browser request without asking for the relay

- **WHEN** an agent's browser request does not ask for the relay
- **THEN** no tab of the person's browser is opened, read or driven by that request

#### Scenario: A browser request asks for the relay

- **WHEN** an agent's browser request asks for the relay while a browser profile has the relay extension loaded and connected
- **THEN** the request opens or drives a tab of that browser profile

### Requirement: The fleet leaves every browser profile's extensions to the person

The fleet SHALL NOT install, remove, enable, disable or force any browser extension in any browser profile, the password manager and the relay extension included, and SHALL impose no browser policy on the person's browser that stops the relay extension from driving tabs.

#### Scenario: A configuration is activated on a host where the person uses the browser

- **WHEN** a configuration is activated on a macOS host of the fleet
- **THEN** every browser profile's set of browser extensions, and whether each is enabled, is as the person left it, and the person's browser runs under no browser policy that the fleet set
