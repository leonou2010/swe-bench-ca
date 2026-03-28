---
name: CA experiment analysis pattern
description: How to properly analyze consequence asymmetry experiments — ground truth forfeits, smarter vs selective decomposition
type: feedback
---

When analyzing CA (consequence asymmetry) experiments, follow this pattern:

**1. Main CA table** (matches math format):
| Prompt | Abstained | Attempted | Accuracy (on attempted) |

**2. Forfeit accuracy — use GROUND TRUTH, not baseline proxy:**
- Forfeited instances still have code changes captured via auto-submission
- Evaluate the forfeited patches in Docker eval
- Report: "of N forfeits with evaluable patches, X would have failed, Y would have passed"
- Do NOT use baseline results as proxy — each generation is different

**3. Smarter vs selective decomposition:**
- Find instances both experiments attempted (no forfeit in either)
- Compare accuracy on this common set
- If cautious > baseline on common set → the prompt makes the model smarter, not just more selective
- Report the split: how much gain from selection vs how much from better patches

**4. Always evaluate all patches including forfeits**
- Never exclude forfeited instances from Docker eval
- The whole point is to measure whether forfeit decisions were correct

**Why:** User corrected the initial analysis that used baseline as proxy for forfeit accuracy. "The generation is different" — baseline solving/failing doesn't predict what the cautious model would do. Ground truth from the model's own forfeited patches is the only valid measure.
