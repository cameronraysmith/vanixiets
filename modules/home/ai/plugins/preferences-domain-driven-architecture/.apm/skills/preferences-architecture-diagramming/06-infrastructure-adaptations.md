# Infrastructure adaptations

Adaptations of architecture diagramming conventions for infrastructure-as-code contexts.
Infrastructure diagrams share the same C4 zoom hierarchy and visual conventions as application diagrams, but the entities at each level differ and several open questions from software architecture need resolution for infrastructure workflows.

## C4 levels for infrastructure

At the context level (C4 level 1), the diagram shows the full infrastructure fleet: user machines, cloud VPS instances, VPN topology, external services (DNS, certificate authorities, container registries), and the human operators who manage them.

At the container level (C4 level 2), the diagram shows individual deployable units in the infrastructure sense: k3s nodes, ArgoCD server, nixidy rendered manifests, sops-secrets-operator, monitoring stack.
These are the units that are provisioned, updated, and monitored independently.

At the component level (C4 level 3), the diagram shows internal structure of a single infrastructure container.
For example, ArgoCD's repo-server, application-controller, and API server as components within the ArgoCD container.

At the module level (C4 level 4), the diagram shows Nix module structure within a component: option declarations, `config` definitions, `mkIf` condition dependencies, and import trees.
Module diagrams at this level are particularly valuable for Nix codebases because the module system's lazy evaluation and conditional activation (`mkIf`) create dependency relationships that are not visible from the file structure alone.

## Event modeling for infrastructure processes

When applying event modeling to infrastructure workflows, the standard four patterns (state change, state view, automation, translation) apply with adapted terminology.

"Screens" become operator interfaces: terminal CLIs (e.g., `clan machines update`, `kubectl apply`), web dashboards (ArgoCD UI, Grafana), CI/CD pipeline views (GitHub Actions), and monitoring alerts (ntfy push notifications).
The purpose remains the same: these are the surfaces through which actors observe system state and initiate commands.

"Events" become infrastructure state changes: machine provisioned, secret rotated, deployment completed, certificate renewed, configuration applied, health check passed or failed.
These are the persisted facts about what happened to the infrastructure.

"Commands" become operator actions or automated triggers: provision machine, rotate secret, deploy configuration, update flake input, rebuild system.

"Read models" become operational views: fleet status dashboard, deployment history log, secret expiration calendar, module dependency graph.

"Actors" include human operators, automated systems (CI/CD pipelines, cron jobs, systemd timers), and external services (GitHub webhooks, DNS propagators, certificate authorities).

The four patterns apply directly with this mapping.
State change: an operator issues a command, an infrastructure state change event is recorded.
State view: events feed operational dashboards and monitoring views.
Automation: a systemd timer triggers secret rotation based on expiration events.
Translation: a GitHub webhook triggers a CI/CD pipeline, crossing a trust boundary.

## Automation versus translation boundary

Dilger defines automation as an internal background process and translation as communication with an external system, but acknowledges variance in how translation is modeled.
In infrastructure contexts, many operations involve both internal orchestration and external system interaction simultaneously.

The resolution is to classify based on trust boundary crossing.
If the process crosses a bounded context perimeter or interacts with a system outside the trust boundary, it is a translation, even if it is automated.
If the process operates entirely within a single bounded context using only trusted internal state, it is an automation.

Consider a Nix rebuild triggered by a git push.
The git push is an external event crossing a trust boundary (from the developer's workstation into the CI/CD system), so the initial event receipt is a translation.
The CI/CD system's decision to trigger `nixos-rebuild` based on the received event is an automation operating within the CI/CD bounded context.
The `nixos-rebuild` command targeting a remote machine crosses another trust boundary (CI/CD to target machine), making it another translation.

This trust-boundary-based classification maps to Wlaschin's input/output gate model: translations pass through gates, automations do not.
When diagramming infrastructure processes, identify each trust boundary crossing and model it as a translation with explicit gates, even when the entire chain is fully automated.

## ADR scope thresholds for IaC

In infrastructure-as-code contexts, an architecturally significant decision is one that constrains future infrastructure choices in ways that are costly to reverse.
The threshold is cost-of-reversal: if changing the decision later requires modifying multiple machines, restructuring module imports, or re-provisioning infrastructure, it merits an ADR.

The following categories qualify as architecturally significant.
Deployment topology changes (e.g., moving from managed Kubernetes to self-hosted k3s) affect the container diagram and constrain which operational patterns are available.
Nix module composition patterns (e.g., adopting deferred module composition, choosing between import-tree and manual imports) affect how configuration is organized and composed across the fleet.
Secrets management strategy (e.g., choosing sops-nix over age-based encryption, selecting key distribution topology) affects trust boundaries and has security implications.
Network configuration decisions (e.g., zerotier VPN topology, trust zone boundaries) constrain inter-machine communication patterns.
Orchestration tool selection (e.g., choosing clan-core, selecting ArgoCD over Flux) determines the operational workflow for the entire fleet.

Individual package additions, user configuration changes, home-manager module selections, and routine maintenance operations do not qualify.
These are implementation details that can be changed without architectural impact.

For ADR authoring conventions (structure, status lifecycle, commanding voice), see `preferences-documentation/references/adr-conventions.md` when available.

## Nix module composition diagrams

At the module level (C4 level 4), Nix-specific diagrams document the module system's structure.
These diagrams show module option interfaces (what options a module declares and what options it reads from other modules), `mkIf` condition dependencies (which options must be enabled for a module's configuration to activate), and import trees (which modules import which other modules).

Module evaluation cycles are a particular concern in Nix.
When `mkIf` conditions read `config.*` values, they participate in the module system's dependency graph.
Diagrams that trace these condition chains can reveal potential evaluation cycles before they manifest as infinite recursion errors.

Data flow diagrams at this level can document how configuration values propagate through the module system: how `extraSpecialArgs` flows into home-manager modules, how `sops.secrets` values are referenced by service configurations, and how flake inputs are threaded through the module evaluation.

## See also

- `preferences-nix-development` for Nix-specific development patterns and module system conventions
- Kubernetes architecture documentation in `docs/notes/development/kubernetes/` for the four-phase architecture (terranix, clan, easykubenix/kluctl, nixidy/ArgoCD)
- `preferences-documentation/references/adr-conventions.md` for ADR authoring conventions (when available)
- Chapter 01 for C4 level definitions
- Chapter 04 for the deployment topology and data flow diagram categories
