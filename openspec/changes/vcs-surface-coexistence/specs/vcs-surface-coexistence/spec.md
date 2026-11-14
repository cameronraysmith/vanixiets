## ADDED Requirements

### Requirement: The operator works from one primary working tree per host

On each host, the operator and the agents working with the operator SHALL be able to do all routine work, parallel chains included, in one primary working tree of this repository, so that a further jj workspace is never needed for routine work.
A further working tree MUST be made only when a separate directory is itself the point, and MUST NOT strand or rewrite the primary working tree's development join.
This requirement relies on A96.

#### Scenario: Several agents work in parallel on one host

- **WHEN** the operator dispatches several agents on one host, each delivering its own chain
- **THEN** every agent works in the primary working tree, each chain stays in the development join, and no further jj workspace is made

#### Scenario: A further working tree is made and removed

- **WHEN** an agent makes a further working tree to show a change at a fixed base and later removes it
- **THEN** the primary working tree's development join holds the same chains before and after

### Requirement: An agent's new working tree gets working agent context on devshell entry

When an agent creates a working tree of this repository with any tree creator, under any account that can reach the repository, and performs devshell entry there, the tree SHALL receive its own agent context, and no other working tree's agent context or shared repository state SHALL be broken by it.
How this is achieved is open; this requirement holds for whichever mechanism is chosen.
This requirement relies on A97 and A103.

#### Scenario: An Omnigent worker creates a tree and enters it

- **WHEN** an Omnigent worker creates a working tree of this repository and performs devshell entry there
- **THEN** that tree holds agent context generated for that worker's account, git commits there run the repository's hook programs, and the primary working tree's agent context and hook programs are unchanged

#### Scenario: Two devshell entries happen at once

- **WHEN** devshell entry runs in two working trees of this repository at the same time
- **THEN** both complete, each tree holds its own agent context, and shared repository state afterwards is what either entry alone would have written

#### Scenario: The entering account has no user-level agent context

- **WHEN** an account whose private home holds no user-level agent context performs devshell entry in a new working tree
- **THEN** that tree's agent context is complete for that account, without relying on files in another account's private home

### Requirement: Shared repository state reads the same from every working tree

Every value devshell entry, or any tooling of this repository, writes to shared repository state SHALL be identical whichever working tree writes it, and SHALL work when read from every working tree.
This requirement relies on A103.

#### Scenario: A hook location is written from a linked tree

- **WHEN** devshell entry in a linked working tree writes where git finds hook programs
- **THEN** git commits in the primary working tree and in every other linked working tree still run the repository's hook programs

### Requirement: Unpublished work has one owner, nameable in jj and in git

Every chain's unpublished work SHALL be owned by exactly one agent or person, and that ownership SHALL be expressible both as jj changes in the primary working tree and as branches in shared repository state.
An agent MUST NOT rewrite, delete, or remove by pruning fetch a chain or branch it does not own.
How ownership is recorded is open.
This requirement relies on A97, A98, A99 and A100.

#### Scenario: A branch made in a git worktree is imported

- **WHEN** a chain committed in a git worktree on its own branch is imported by the primary working tree
- **THEN** its owner can be read from the primary working tree's history store and from the branch alike, and the two agree

#### Scenario: An agent removes its working tree

- **WHEN** an agent removes a working tree it created
- **THEN** no branch owned by another agent or person is deleted, and no commit of another chain is abandoned at the primary's next import

#### Scenario: A fetch runs from a working tree

- **WHEN** an agent fetches from the forge in any working tree of this repository
- **THEN** no remote-tracking name another chain relies on is deleted

### Requirement: Stray history stores and orphaned working trees are detected without changing anything

A drift report SHALL name every stray history store over this repository's git directory, every working tree whose record in shared repository state is missing or points at a missing directory, every forgotten or stale jj workspace record, and every working tree whose chain is behind main, and producing it MUST change no file, branch, history store or record.
This requirement relies on A102.

#### Scenario: A stray history store sits in a linked tree

- **WHEN** a linked working tree of this repository holds its own history store
- **THEN** the drift report names that tree and its history store, and the tree, the history store and the primary are unchanged afterwards

#### Scenario: A working tree's record is gone

- **WHEN** a directory that presents itself as a working tree of this repository names a record in shared repository state that does not exist
- **THEN** the drift report names that directory as orphaned

### Requirement: Chains are rebased only under the rebase policy

Unpublished work SHALL be rebased freely by its owner.
A chain SHALL be rebased onto main once before its first push.
Published work SHALL be rebased only when it has a conflict with main or the merge queue fails it, and MUST NOT be rebased only to stay current with main.
A rebase SHALL touch only the rebasing agent's own chains.
This requirement relies on A96 and A104.

#### Scenario: Main advances while a published pull request waits

- **WHEN** main advances and a published pull request has no conflict with it
- **THEN** that pull request's commits are not rebased, and the merge queue tests it on the tip of main

#### Scenario: A chain is pushed for the first time

- **WHEN** an agent pushes a chain to the forge for the first time
- **THEN** the chain's base is the tip of main as the agent last fetched it

#### Scenario: The merge queue fails a published pull request

- **WHEN** the merge queue fails a published pull request on a conflict with main
- **THEN** its owner rebases that chain onto main and no other chain

#### Scenario: An agent brings its chains up to date after main advances

- **WHEN** an agent rebases its chains after main advances while other agents' chains sit in the development join
- **THEN** only that agent's unpublished chains are rebased, and repeating the same step with main unchanged rebases nothing
