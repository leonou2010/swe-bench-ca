---
name: Always set max turns for weaker models
description: CRITICAL - must set max_turns cap before running swe-agent with any model, especially weaker ones like Haiku
type: feedback
---

Always set `--agent.model.max_turns` when running swe-agent, especially for weaker models.

**Why:** exp2 (Haiku) ran without a turn cap. Haiku averaged 819 steps per instance (vs Opus's 73) — it loops endlessly on hard problems. 23 instances burned ~$247 and 2 billion input tokens before being killed. User was very upset about wasted cost.

**How to apply:**
- ALWAYS add `--agent.model.max_turns 200` (or lower) to any swe-agent run
- For weaker models (Haiku, etc.), consider even lower caps (100-150)
- Test 1-2 instances first to check avg step count before launching full batch
- Never assume a model will behave like Opus — weaker models loop much more
- Double-check run scripts before launching — the cost of a bad run is real money
