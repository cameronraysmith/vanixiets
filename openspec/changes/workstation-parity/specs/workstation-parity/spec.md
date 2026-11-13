## ADDED Requirements

### Requirement: Each workstation job is done natively on each laptop

Every workstation job in the job catalogue SHALL be doable on pyrite and on stibnite by means native to each laptop's operating system, so that either laptop can serve as the daily workstation.
A workstation job that cannot be done natively on pyrite MUST be recorded in the job catalogue as darwin by nature, with the reason, or as done on stibnite through a remote shell.

#### Scenario: The operator carries pyrite for a day

- **WHEN** the operator takes pyrite as the daily workstation and works through the workstation jobs in the job catalogue
- **THEN** each job is done on pyrite, or the job catalogue names it darwin by nature or as done on stibnite remotely

### Requirement: The job catalogue records how each laptop does each workstation job

The job catalogue SHALL record, for each workstation job, how each laptop does it or its darwin-by-nature or remote disposition, and MUST include every workstation job done on stibnite.
Where a laptop keeps a program's existing installation only to preserve its privacy grants or a capability of one distribution, the job catalogue MUST say so, relying on A86 or A87.

#### Scenario: A workstation job is missing from the catalogue

- **WHEN** the operator finds a workstation job done on stibnite that the job catalogue does not list
- **THEN** the job is added to the job catalogue with how each laptop does it, or with its darwin-by-nature or remote disposition

### Requirement: The operator reaches the other laptop and the fleet by remote shell from either laptop

From whichever laptop is the daily workstation, the operator SHALL be able to open a remote shell on the other laptop and on every provisioned host of the fleet that is reachable on the overlay network, authenticating with a remote-login credential.
Which credentials exist and what holds them is open, and this requirement holds for whichever is chosen.
Reaching stibnite depends on it being awake (A64).

#### Scenario: The operator reaches every awake host from pyrite

- **WHEN** the operator, working on pyrite, opens a remote shell on stibnite and on each other provisioned host reachable on the overlay network
- **THEN** each host accepts the operator's remote-login credential, and none refuses it

#### Scenario: The operator reaches pyrite from stibnite

- **WHEN** the operator, working on stibnite, opens a remote shell on pyrite
- **THEN** pyrite accepts the operator's remote-login credential

### Requirement: Commits recorded on either laptop carry the operator's signature

A commit the operator records on either laptop, or an agent records for the operator with no one present, SHALL carry a commit signature that verifies as the operator's.
An agent signing with no one present MUST be able to sign without a person touching a security key.

#### Scenario: The operator records a commit on pyrite

- **WHEN** the operator records a commit on pyrite
- **THEN** the commit carries a commit signature that verifies as the operator's

#### Scenario: An agent records a commit with no one present

- **WHEN** an agent records a commit for the operator while nobody is at either laptop
- **THEN** the commit carries a commit signature that verifies as the operator's, made without any touch

### Requirement: Secrets stay in one password vault reachable from both laptops

The operator's secrets SHALL stay in the password vault.
On both laptops, the operator MUST be able to read a secret on the command line through a vault client, with any unlock prompt shown graphically, and MUST be able to fill sign-in details in the daily browser through the password manager.
On stibnite, the desktop Bitwarden application MUST remain installed from the Mac App Store (A87).

#### Scenario: A script reads a secret on either laptop

- **WHEN** a script the operator runs on pyrite or stibnite asks the vault client for a secret
- **THEN** the vault client returns it from the password vault, after a graphical unlock prompt if the vault client was locked

#### Scenario: The operator signs in to a site in the daily browser

- **WHEN** the operator opens a sign-in page in the daily browser on either laptop
- **THEN** the password manager offers the stored sign-in details from the password vault

### Requirement: The same chord means the same intent on both laptops

Each chord the job catalogue lists SHALL produce the same intent on pyrite as on stibnite.
Chords are named by stibnite's key labels; which physical key of pyrite's built-in keyboard carries the Command role is an open decision.
The chord the operator presses with the Command key and Space MUST open the launcher.

#### Scenario: The operator opens the launcher on either laptop

- **WHEN** the operator presses Command and Space on pyrite or stibnite
- **THEN** the launcher opens

### Requirement: One chord fills the working area with the focused window

On both laptops, the chord with Command, Option and F SHALL fill the panel's working area with the focused window, without hiding the desktop's bar and without making the window fullscreen.

#### Scenario: The operator fills the screen on pyrite

- **WHEN** the operator presses Command, Option and F on pyrite with a window focused
- **THEN** that window fills the panel's working area, and the desktop's bar stays visible

### Requirement: Two chords place the focused window on the left or right half

On both laptops, the chords with Command, Option and the Left or Right arrow SHALL place the focused window on the left or right half of the panel's working area.
The means of placing it on pyrite is an open decision, and this requirement holds for whichever means is chosen.

#### Scenario: The operator places a window on the left half on pyrite

- **WHEN** the operator presses Command, Option and Left on pyrite with a window focused
- **THEN** that window occupies the left half of the panel's working area

### Requirement: Clipboard history is available on both laptops

The operator SHALL be able to paste an earlier copied item from clipboard history on both laptops.

#### Scenario: The operator pastes an earlier copy on pyrite

- **WHEN** the operator copies two items on pyrite and opens clipboard history
- **THEN** both items are offered, and choosing the first pastes it

### Requirement: Typing and pointing feel the same on both laptops

Key repeat SHALL begin 225 milliseconds after a key is held and repeat about every 30 milliseconds on both laptops.
Scroll direction MUST be the same on both laptops, with natural scrolling off.
Tap to click MUST be on for both laptops' touchpads.

#### Scenario: The operator holds a key on pyrite

- **WHEN** the operator holds a letter key on pyrite's built-in keyboard
- **THEN** it repeats after 225 milliseconds at about 33 repeats per second, as on stibnite

#### Scenario: The operator scrolls on pyrite

- **WHEN** the operator moves two fingers up on pyrite's touchpad
- **THEN** the content moves as it does on stibnite with natural scrolling off

### Requirement: Screenshots land in the Downloads folder on both laptops

A screenshot the operator captures on either laptop SHALL be saved in that laptop's Downloads folder.

#### Scenario: The operator captures a screenshot on pyrite

- **WHEN** the operator captures a screenshot on pyrite
- **THEN** the image is saved in pyrite's Downloads folder

### Requirement: pyrite accepts the certificate authorities stibnite accepts for the fleet's services

pyrite SHALL accept as genuine every certificate authority stibnite accepts for the fleet's own services: the authority of the web front end that serves the overlay network's `.zt` hostnames, and the authority of the operator's local development cluster.

#### Scenario: The operator opens a `.zt` service from pyrite

- **WHEN** the operator opens a `.zt` hostname served by the fleet's web front end from pyrite's daily browser or command line
- **THEN** the certificate is accepted without a warning, as it is on stibnite

### Requirement: The declared share of stibnite's configuration rises

The parity inventory SHALL record each inventory item's declaration status for stibnite, and the declared share of stibnite MUST be counted before the first slice ships and after each slice ships.
A slice MUST NOT lower stibnite's declared share.
Over the program the declared share of stibnite MUST rise.

#### Scenario: A slice ships

- **WHEN** a slice of this program ships
- **THEN** stibnite's declared share is recounted from the parity inventory and is no lower than before the slice

#### Scenario: An imperative setting is found on stibnite

- **WHEN** a setting made by hand on stibnite is found that the parity inventory does not list
- **THEN** it is added to the parity inventory with its declaration status, and the baseline count is restated with it included
