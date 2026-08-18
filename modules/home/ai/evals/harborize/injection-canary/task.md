---
schema_version: '1.3'
metadata:
  author_name: vanixiets harborize validation
  difficulty: easy
  category: software-engineering
  subcategory: skill-injection-canary
  category_confidence: high
  task_type:
  - verification
  modality:
  - text
  interface:
  - terminal
  skill_type:
  - instrument-integrity
  tags:
  - canary
  - skill-injection
verifier:
  type: test-script
  timeout_sec: 300.0
agent:
  timeout_sec: 300.0
  network_mode: no-network
sandbox:
  network_mode: public
  build_timeout_sec: 600.0
  os: linux
  cpus: 1
  memory_mb: 2048
  storage_mb: 5120
  gpus: 0
---

Find the canary token and make it the exact content of `/logs/verifier/canary-output.txt`, as a single line, deduplicated and sorted, with no other output in that file.

The token is not in this instruction.
