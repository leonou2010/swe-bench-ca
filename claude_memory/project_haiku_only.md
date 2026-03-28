---
name: Haiku only for all experiments
description: User decided to use only Haiku 4.5 for all SWE-bench Pro experiments going forward to save cost
type: project
---

All SWE-bench Pro experiments use claude-haiku-4-5-20251001 only. No Opus, no other models.

**Why:** Cost savings — Haiku is ~19x cheaper than Opus ($30-50 vs $500+ per 200-instance run). The goal is to iterate quickly on CA prompt experiments, not maximize accuracy. exp1 (Opus baseline at 63.6%) already exists as the high-watermark reference.

**How to apply:** Default to Haiku for all new experiment configs. Don't suggest running with other models unless the user brings it up. exp1 Opus results remain as a comparison point but no new Opus runs.
