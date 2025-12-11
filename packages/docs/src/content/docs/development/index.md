---
title: Contents
sidebar:
  order: 1
---

Development documentation organized using AMDiRE (Architecture, Monitoring, Development, Integration, Release, Evaluation) principles.

## Sections

- [Architecture](/development/architecture/) - Architectural decisions and technical design documentation
- [Traceability](/development/traceability/) - Requirements traceability and CI/CD philosophy

The documentation follows AMDiRE's three-layer structure:

```mermaid
flowchart TB
    subgraph context["Context Layer"]
        scope["Project Scope"]
        stakeholders["Stakeholders"]
        goals["Goals"]
        constraints["Constraints"]
    end

    subgraph requirements["Requirements Layer"]
        vision["System Vision"]
        usage["Usage Model"]
        functional["Functions"]
        quality["Quality"]
    end

    subgraph solution["Solution Layer"]
        archspec["Architecture"]
        adrs["ADRs"]
        traceability["Traceability"]
    end

    context --> requirements
    requirements --> solution
```
