---
name: Never overwrite experiment results
description: CRITICAL - always use new output directories for re-runs, never clean previous results
type: feedback
---

Never delete or overwrite previous experiment results, even if the experiment had bugs. The data is still useful for analysis.

**Why:** exp5 was re-run with exit_forfeit fix, but launch.sh cleaned the old results directory. User explicitly said "please don't overwrite anything, even the exp was wrong, the data are still useful."

**How to apply:**
- For re-runs, use a new output directory (e.g., `swe_agent_ultra_cautious_v2`)
- Never put `rm -rf` of results dirs in launch scripts
- If a re-run is needed, create a new exp folder or append a version suffix
- Old data with bugs is still analyzable — it shows what the model tried to do even when infrastructure failed
