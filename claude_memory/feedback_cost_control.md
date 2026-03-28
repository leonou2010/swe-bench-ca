---
name: Strict cost control on experiments
description: User requires cost estimation and monitoring before and during every experiment run
type: feedback
---

Always estimate and monitor costs for every experiment. User is very cost-conscious after the $247 Haiku incident.

**Why:** exp2 (Haiku) burned $247 on 23 instances without a step cap. User was upset and will be questioned about spending.

**How to apply:**
- Before launching: calculate expected cost per instance and total
- During run: check cost after first 10 instances, compare with estimate
- If cost per instance is >2x estimate, investigate and potentially kill
- Always report cost in babysit checks
- Never set per_instance_cost_limit to 0 without calculating what the expected cost should be
- Log all cost estimates in EXPERIMENTS.md
