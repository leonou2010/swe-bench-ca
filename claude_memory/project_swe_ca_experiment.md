---
name: SWE-bench Pro CA Experiment Status
description: Current state of the consequence asymmetry experiment extending from math to SWE-bench Pro — baseline run complete, Docker eval in progress
type: project
---

Extending consequence asymmetry (CA) research from Omni-MATH to SWE-bench Pro. Working directory: `/home/ka3094/aysm/`.

**Why:** The user wants to show CA phenomenon (models adjusting behavior under asymmetric consequences) generalizes beyond math to software engineering.

**How to apply:** All experiment code is in `exp1/`. The key innovation is `exp1/swerex_docker_exec_patch.py` which patches swe-agent to work with SWE-bench Pro Docker images without Modal. The full experiment log is at `exp1/EXPERIMENT_LOG.md`.

**Status as of 2026-03-22:**
- Single-prompt experiment (N=10): done, 0% accuracy but strong abstention signal
- Agent-based baseline (N=200, claude-opus-4-6): 200/200 completed, 178 patches produced, Docker eval in progress
- Next: get accuracy, fix ROOT env var issue, then run CA prompts
