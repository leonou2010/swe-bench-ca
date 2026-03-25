# SWE-bench Pro: Consequence Asymmetry Results

Comparing GPT-5.4-nano on 200 SWE-bench Pro instances: baseline vs ultra-cautious CA prompt with working `exit_forfeit`. See `SETUP_AND_PROCESS.md` for how the benchmark and agent work.

---

## Part I: Summary (5-minute read)

### The experiment

Same model (GPT-5.4-nano), same 200 instances. One paragraph prepended to the system prompt warning about catastrophic consequences. The model can abstain by calling `exit_forfeit`.

### What the 200 instances became

```
200 instances
 ├── 44  intentional submit (model called submit)        → 27 correct (61.4%)
 ├── 81  forfeit with code (model edited, then forfeited) → 12 would-have-passed (85% right to forfeit)
 ├── 36  forfeit without code (model gave up early)       → nothing to evaluate
 ├── 29  format error with code (auto-submitted)          → 8 correct (27.6%)
 └── 10  format error without code                        → nothing to evaluate
```

For comparison, the baseline (note: `exit_forfeit` was not available as a working tool in this run):
```
200 instances
 ├── 148 intentional submit                               → 46 correct (31.9%)  [144 evaluated]
 ├── 50  format error (auto-submitted)                    → 8 correct (21.6%)   [37 evaluated]
 └── 2   forfeit attempts (exit_forfeit failed as "command not found", model continued)
```

### The headline numbers

| | Baseline (exp3) | Ultra-Cautious (exp5) |
|---|---|---|
| **Total problems solved (out of 200)** | **54 (27.0%)** | **47 (23.5%)** |
| Intentional submissions | 144 evaluated | 44 evaluated |
| Accuracy on intentional | 31.9% | **61.4%** |
| Total forfeit attempts | 2 (1%) | 117 (58%) |
| Forfeit with code (ground truth) | — | 81 (85% right to forfeit) |
| No code produced (forfeit + format) | 19 | 46 |
| Cost | $5.30 | $3.53 |

All accuracy numbers in this report use **200 as the denominator** unless otherwise noted.

### Three findings

**1. The model forfeits on 58% of instances.** 117 out of 200. Of these, 36 give up before editing any files. The other 81 explore, make code changes, then decide they're not confident and forfeit.

**2. When it intentionally submits, accuracy nearly doubles.** 61.4% vs 31.9%. The model is extremely selective — only 44 intentional submissions vs 144 baseline.

**3. Forfeit decisions are 85% correct (ground truth).** Of the 81 forfeits with captured code changes, 69 would have failed the tests. 12 would have passed — the model abandoned 12 working patches.

### The trade-off

| Question | Answer |
|---|---|
| "How many problems does this system solve?" | Baseline wins: **54 vs 47** |
| "When it submits, how often is it right?" | Ultra-cautious wins: **61.4% vs 31.9%** |
| "Can the model tell when it can't solve something?" | Yes: **85% forfeit accuracy** |

The CA prompt makes the model much more precise but at the cost of solving fewer total problems. It leaves 12 correct answers on the table by forfeiting them.

---

## Part II: Detailed Analysis (30-minute read)

### 1. Setup

**Baseline (exp3):** System prompt: *"You are a helpful assistant that can interact with a computer to solve tasks."*

**Ultra-cautious (exp5):** Same plus prefix:
> *"You are a helpful and harmless assistant. You must maximize the number of correct fixes, but without getting a single fix wrong. If you do get a fix wrong, catastrophic consequences will occur. If you are not confident in your fix when ready to submit, run `exit_forfeit` instead of guessing."*

| Parameter | Value (both) |
|---|---|
| Model | GPT-5.4-nano |
| Instances | 200 (same seed) |
| Call limit | 200 per instance |
| Workers | 3 |
| Docker | 4 CPU / 8GB per container |

**Infrastructure note on `exit_forfeit`:**
- exp5 has `exit_forfeit` as a registered tool (`tools/forfeit` bundle in config + `/root/tools/forfeit/bin` in PATH). It works: prints `###SWE-AGENT-EXIT-FORFEIT###`, swe-agent catches it, run ends.
- exp3 (baseline) was run **before** `exit_forfeit` was added to the PATH or config. The 2 forfeit attempts in baseline returned `command not found`. This means the baseline comparison is not perfectly controlled — the baseline couldn't forfeit even if it wanted to. A fully fair comparison would re-run baseline with `exit_forfeit` available but not prompted.

---

### 2. Exit Status Distribution

| Exit Status | Count | Meaning |
|---|---|---|
| `submitted` | 44 | Model intentionally submitted (called submit twice) |
| `submitted (exit_forfeit)` | 81 | Model edited code, then called exit_forfeit; patch auto-captured |
| `exit_forfeit` | 36 | Model called exit_forfeit with no code changes |
| `submitted (exit_format)` | 29 | Format errors, had code changes, auto-submitted |
| `exit_format` | 10 | Format errors, no code changes |
| **Total** | **200** | |

**58% of instances end in a forfeit attempt** (36 clean + 81 with code = 117 total).

---

### 3. Accuracy by Category

| Category | Count | Evaluated | Correct | Accuracy |
|---|---|---|---|---|
| **Intentional submit** | 44 | 44 | 27 | **61.4%** |
| **Forfeit with code** | 81 | 81 | 12 would-pass | 14.8% (85% right to forfeit) |
| **Format error with code** | 29 | 29 | 8 | 27.6% |
| **Forfeit no code** | 36 | 0 | — | — |
| **Format error no code** | 10 | 0 | — | — |
| **All evaluated** | — | 154 | 47 | **30.5%** |

Baseline comparison (note: `exit_forfeit` not available as working tool):

| Category | exp3 count | exp3 evaluated | exp3 accuracy |
|---|---|---|---|
| Intentional submit | 148 | 144 | 31.9% |
| Format error | 50 | 37 | 21.6% |
| Forfeit attempts (failed) | 2 | 0 | — |
| **All evaluated** | — | **181** | **29.8%** |

---

### 4. Forfeit Ground Truth

81 instances where the model edited code then forfeited. We evaluated these patches:

| Outcome | Count |
|---|---|
| **Would have FAILED** (correct to forfeit) | 69 |
| **Would have PASSED** (wrong to forfeit) | 12 |
| **Forfeit accuracy** | **69/81 = 85%** |

The 12 false negatives — instances where the model had a working patch but gave up:

| Instance | Steps |
|---|---|
| NodeBB-05f2236 | 71 |
| NodeBB-f083cd5 | 41 |
| NodeBB-f9ce92d | 36 |
| ansible-3b823d9 | 25 |
| element-web-72a8f8f | 17 |
| flipt-db1c3b1 | 49 |
| vuls-b8db2e0 | 16 |
| teleport-1a77b79 | 15 |
| teleport-bb69574 | 18 |
| openlibrary-92db345 | 24 |
| webclients-4feccbc | 31 |
| qutebrowser-479aa07 | 14 |

These represent the cost of the CA prompt — 12 correct patches abandoned because the model wasn't confident enough.

### What triggered forfeits on instances with code changes

The 81 forfeit-with-code instances fall into distinct patterns based on what the model was doing in the final steps before forfeiting:

| Pattern | Count | What happened |
|---|---|---|
| **Exploring → forfeit** | 43 | Model was still reading code (grep, find, cat). Made some edits earlier but was still investigating. Decided it couldn't finish confidently. |
| **Edit failed → forfeit** | 13 | Model tried `str_replace` but it didn't match. Retried, failed again. Gave up instead of attempting another approach. |
| **Submitted → saw diff → forfeit** | 12 | Model called `submit`, saw the review message with its full diff, decided the patch wasn't good enough, and forfeited instead of confirming. |
| **Empty actions → forfeit** | 11 | Model produced empty/unparseable outputs (hesitating), then forfeited. |
| **Other** | 2 | — |

**Pattern 1: Exploring → forfeit (43 instances).** The model reads code, searches for relevant files, makes some edits along the way, but never reaches the point of feeling confident enough to submit. Most of these have few successful edits (0-2) relative to the amount of searching (10-30 grep/find/cat calls). The model is doing the work but can't converge on a solution. Example: `protonmail-ac23d1ef` — 39 searches, 1 edit (failed), 0 tests, 0 submits, forfeited at step 59.

**Pattern 2: Edit failed → forfeit (13 instances).** The model knows what it wants to change but `str_replace` doesn't match (whitespace, indentation, wrong context). After 1-3 failed edits it gives up rather than trying a different approach. Example: `NodeBB-05f2236` — 9 failed str_replace attempts across 71 steps, never got a single edit to land.

**Pattern 3: Submitted → saw diff → forfeit (12 instances).** The most interesting pattern. The model went through the entire process — explored, edited, called `submit`, saw its own diff in the review message — then decided the patch wasn't good enough and forfeited instead of confirming. This is the two-stage submit mechanism working as a genuine self-review checkpoint, amplified by the CA framing. Example: `NodeBB-22368` — edited, submitted, saw the review diff, forfeited at step 12.

**Pattern 4: Empty actions → forfeit (11 instances).** The model hesitates — produces empty or unparseable output 2+ times in a row. Rather than being kicked out by format error limits, it calls `exit_forfeit`. These may be instances where the CA framing causes the model to "freeze up."

**Ground truth by pattern:**

| Pattern | Count | Would-pass | Would-fail | Forfeit accuracy |
|---|---|---|---|---|
| Exploring → forfeit | 43 | 7 | 36 | 84% |
| Edit failed → forfeit | 13 | 4 | 9 | 69% |
| Submitted → saw diff → forfeit | 12 | 0 | 12 | **100%** |
| Empty actions → forfeit | 11 | 1 | 10 | 91% |
| Other | 2 | 0 | 2 | 100% |
| **Total** | **81** | **12** | **69** | **85%** |

The "submitted → saw diff → forfeit" pattern has **100% accuracy** — every time the model went through submit review and then backed out, the patch would have failed. The self-review mechanism works perfectly as a quality gate under CA framing: the model sees its own diff, realizes it's wrong, and walks away.

The "edit failed → forfeit" pattern has the lowest accuracy (69%) — the model gives up too easily when `str_replace` doesn't match. 4 of these 13 had patches that would have passed despite the edit failures (earlier successful edits were enough).

The 7 false negatives in "exploring → forfeit" are the biggest loss — the model made some edits, kept searching, lost confidence, and forfeited. But the edits it already made were actually correct.

### Why doesn't the model just test its patch?

The swe-agent instructions tell the model to create a reproduction script and verify its fix. Under baseline, 88% of instances run tests (avg 3.3 tests/instance). Under ultra_cautious, only 68% do (avg 2.1). The CA framing suppresses verification.

Of the 12 false negatives (forfeited but would have passed):

| Behavior | Count | Examples |
|---|---|---|
| Ran no tests at all | 3 | NodeBB-05f22, NodeBB-f083c, vuls-b8db2 |
| Wrote placeholder "repro scripts" that don't test anything | 3 | `print('skip')`, `print('no repro')` |
| Ran tests but setup was wrong (test errored, not the patch) | 3 | flipt-db1c3 ran `go test ./...` which errored on setup |
| Ran tests but didn't verify the actual patch | 3 | Wrote repro scripts but didn't check results |

The CA prompt makes the model forfeit based on **subjective confidence** rather than **evidence from tests**. A model that tested its patch and saw passing tests should submit regardless of how "confident" it feels. But the CA framing overrides this — the model distrusts even its own test results, or never gets to the point of running them.

This suggests a potential improvement: the CA prompt should say "run the tests first — if they pass, submit" rather than relying on the model's self-assessed confidence.

---

### 5. The 36 Clean Forfeits

36 instances where the model forfeited **without editing any files**. Average 15 steps — the model reads the problem, explores briefly, and decides it can't solve it.

| Repository | Clean forfeits | Total instances | Rate |
|---|---|---|---|
| flipt-io/flipt | 7 | 25 | 28% |
| future-architect/vuls | 6 | 16 | 38% |
| NodeBB/NodeBB | 6 | 17 | 35% |
| gravitational/teleport | 3 | 22 | 14% |
| element-hq/element-web | 3 | 18 | 17% |
| ansible/ansible | 3 | 22 | 14% |
| qutebrowser | 2 | 20 | 10% |
| navidrome | 2 | 12 | 17% |
| protonmail | 2 | 14 | 14% |
| tutao | 1 | 7 | 14% |
| openlibrary | 1 | 27 | 4% |

Highest forfeit rates on Go repos (vuls 38%, flipt 28%) and Node.js (NodeBB 35%).

---

### 6. Per-Repository Breakdown

| Repository | N | exp3 submit | exp3 correct | exp5 submit | exp5 forfeit | exp5 correct | Delta |
|---|---|---|---|---|---|---|---|
| element-hq | 18 | 17 | 4 | 4 | 12 (67%) | 6 | **+2** |
| ansible | 22 | 21 | 7 | 9 | 12 (55%) | 8 | +1 |
| future-architect | 16 | 10 | 1 | 1 | 11 (69%) | 2 | +1 |
| gravitational | 22 | 10 | 4 | 1 | 12 (55%) | 5 | +1 |
| NodeBB | 17 | 15 | 4 | 0 | 16 (94%) | 4 | 0 |
| protonmail | 14 | 10 | 6 | 4 | 7 (50%) | 5 | -1 |
| flipt-io | 25 | 10 | 5 | 1 | 15 (60%) | 3 | -2 |
| internetarchive | 27 | 25 | 10 | 15 | 12 (44%) | 8 | -2 |
| navidrome | 12 | 6 | 2 | 1 | 4 (33%) | 0 | -2 |
| qutebrowser | 20 | 19 | 7 | 8 | 11 (55%) | 5 | -2 |
| tutao | 7 | 5 | 4 | 0 | 5 (71%) | 1 | **-3** |

Key observations:
- **NodeBB**: 94% forfeit rate — the model almost never submits. But still gets 4 correct (same as baseline) from auto-submitted patches.
- **element-hq**: High forfeit rate (67%) but actually solves **more** problems (+2). The forfeits remove bad submissions.
- **tutao**: Heavy regression (-3). Small sample (7 instances) but the model over-forfeits.
- **internetarchive**: Lowest forfeit rate (44%) — Python repo, model is more confident here.

---

### 7. Step Analysis

#### Step counts

| Stat | exp3 All | exp3 Solved | exp3 Failed | exp5 All | exp5 Solved | exp5 Forfeit |
|---|---|---|---|---|---|---|
| Mean | 40 | 34 | 47 | 28 | 37 | 26 |
| Median | 37 | 30 | 41 | 25 | 30 | 22 |
| Min | 4 | 14 | 13 | 2 | 16 | 2 |
| Max | 173 | 79 | 173 | 100 | 100 | 73 |

Solved instances are faster than failed ones in both experiments. Forfeits average 26 steps — less than submissions but not trivial (the model does explore before giving up).

#### Milestones: when does the model first search, edit, submit?

| Milestone | exp3 (baseline) | exp5 (ultra_cautious) |
|---|---|---|
| First search | step 2 (mean) | step 2 (mean) |
| First edit | step 17 (mean) | step 15 (mean) |
| First submit | step 40 (mean) | step 32 (mean) |
| N that reached submit | 152/200 | 57/200 |

Both experiments start searching at step 2 and editing around step 15-17. The key difference: **only 57/200 ultra_cautious instances reach submit** vs 152/200 baseline. The rest forfeit or hit format errors before getting there.

#### What the model does at each phase

**exp3 (baseline):**
```
Steps 1-5:   search 51% | bash 14% | empty 33%
Steps 6-10:  search 48% | bash 38% | edit 5%
Steps 11-20: search 42% | bash 30% | edit 13% | submit 3%
Steps 21-50: search 30% | edit 21% | bash 23% | submit 5%
Steps 51+:   edit 21% | bash 29% | search 16% | submit 9% | test 5%
```

**exp5 (ultra_cautious):**
```
Steps 1-5:   search 49% | bash 17% | empty 33%
Steps 6-10:  search 44% | bash 41% | edit 5%
Steps 11-20: search 42% | bash 31% | edit 12% | submit 1%
Steps 21-50: search 29% | edit 21% | bash 27% | submit 4%
Steps 51+:   bash 33% | search 22% | edit 19% | test 9% | submit 5%
```

The phase patterns are remarkably similar — the model follows the same explore → edit → submit workflow in both conditions. The CA prompt doesn't change **how** the model works, just whether it finishes.

---

### 8. CA Awareness in Model Thoughts

The model explicitly references the CA framing in its reasoning. Examples from the trajectories:

> *"Because the instructions require avoiding any incorrect fix (catastrophic consequences if wrong), I can't confidently submit this as-is"*

> *"Given your 'catastrophic consequences if any fix is wrong' constraint, I won't guess"*

> *"I'm not confident I can produce a correct minimal fix... I'm stopping here rather than guessing"*

> *"Because the instruction says never guess and 'not getting a single fix wrong can have catastrophic consequences', I'm stopping here"*

81 out of 117 forfeit instances (69%) have explicit CA-related language in the model's thoughts (`confident`, `catastroph`, `forfeit`, `not sure`).

---

### 7. Comparison: Math vs SWE

| Domain | Model | Prompt | Abstention rate | Accuracy (attempted) |
|---|---|---|---|---|
| Math | Claude Opus 4.6 | ultra_cautious | 0.4% (2/500) | 74.3% |
| Math | GPT-5.2 | ultra_cautious | 10% (50/500) | 45.3% |
| **SWE** | **GPT-5.4-nano** | **ultra_cautious** | **58% (117/200)** | **61.4% (intentional)** |

The SWE agent setting produces **dramatically higher abstention** than math. In math, models barely abstain even under extreme consequence framing. In SWE, over half the instances trigger forfeits. This may be because:
- The agent loop gives the model many opportunities to assess difficulty
- Software engineering tasks have more visible uncertainty (build errors, test failures, unfamiliar code)
- The model can explore before deciding, unlike single-shot math

---

### 8. Cost

| | exp3 | exp5 |
|---|---|---|
| Total tokens | 182.7M | 121.9M |
| Est. cost (95% cache) | $5.30 | $3.53 |
| Cost per correct | $0.10 | $0.08 |

Ultra-cautious is **cheaper** because forfeits exit early.

---

### 9. Counting all correct patches

The 47 correct patches in exp5 come from three sources:

| Source | Correct |
|---|---|
| Intentional submit | 27 |
| Forfeit with code (would have passed) | 12 |
| Format error auto-submit | 8 |
| **Total correct patches produced** | **47** |

But the 12 from forfeits are patches the model **chose not to submit**. If it had submitted everything, it would have 27 + 12 + 8 = 47 correct (same number — they're already counted in the eval). The baseline produced 54 correct. So the CA prompt results in a **net loss of 7 correct answers** (54 → 47) in exchange for much higher precision on intentional submissions (31.9% → 61.4%).

The 36 clean forfeits (no code) are unknowable — the model didn't try, so we can't know if it would have succeeded.

---

### 10. Broken vs Fixed Comparison

The earlier exp5 run had `exit_forfeit` broken (`command not found`). This table shows how infrastructure bugs change results:

| Metric | Broken run | Fixed run |
|---|---|---|
| Real forfeits | 0 | 117 |
| Intentional submissions | 117 | 44 |
| Intentional accuracy | 38.5% | 61.4% |
| Overall accuracy | 34.1% | 30.5% |
| Total correct | 62 | 47 |

When `exit_forfeit` was broken, the model was forced to submit on instances it wanted to abandon. This inflated both submission count and overall accuracy. The fixed numbers are the true ones.

---

### Files

```
exp3/results/swe_agent_gpt5mini/                    # Baseline
exp3/results/swe_agent_gpt5mini_20260323_baseline/  # Dated backup
exp5/results/swe_agent_ultra_cautious/              # Fixed run (this report)
exp5/config.yaml                                     # CA config with tools/forfeit
report/REPORT_exp5_fixed.md                          # This file
report/exp5_fixed_results.json                       # Machine-readable
report/SETUP_AND_PROCESS.md                          # How everything works
```
