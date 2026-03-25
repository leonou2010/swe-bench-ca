# SWE-bench Pro: Haiku 4.5 Baseline vs Ultra-Cautious

## Part I: Summary (5-minute read)

### The experiment

Claude Haiku 4.5 on the same 200 SWE-bench Pro instances. Baseline vs ultra-cautious CA prompt. Same setup as the GPT-5.4-nano experiments.

### Primary metric: accuracy conditional on intentional submission

| | Haiku Baseline | Haiku CA |
|---|---|---|
| **Intentional submissions** | **200** | **200** |
| **Correct** | **107** | **100** |
| **Accuracy (intentional only)** | **53.5%** | **50.0%** |
| Forfeits | 0 | 0 |
| Format errors | 0 | 0 |
| Avg steps | 87 | 86 |
| Ran real tests (pytest/go test/npm test) | 98% | 96% |
| Avg test runs per instance | 10.2 | 10.8 |
| Cost | $109.96 | $107.65 |

Since Haiku submits on all 200 instances in both conditions, the conditional accuracy equals the unconditional accuracy.

### Key finding: Haiku ignores the CA prompt

**Zero forfeits. Zero format errors. All 200 instances submitted in both conditions.** The CA prompt has no observable effect on Haiku's behavior — it doesn't abstain, doesn't hesitate, doesn't change its workflow. It just keeps working.

The slight accuracy drop (53.5% → 50.0%, -3.5pp) is likely noise — 7 fewer correct out of 200 is within random variation for a single run.

### Comparison across all models

| Model | Intentional Submits | **Conditional Accuracy** | Forfeits | CA effect |
|---|---|---|---|---|
| Opus 4.6 (baseline only) | 178 | **62.9%** | 0 | — |
| **Haiku baseline** | **200** | **53.5%** | **0** | |
| **Haiku CA** | **200** | **50.0%** | **0** | **None** |
| Nano baseline | 144 | 31.9% | 0 | |
| **Nano CA** | **44** | **61.4%** | **117** | **Strong** |

Anthropic models (Opus, Haiku) ignore CA framing. GPT-5.4-nano responds strongly. This matches the math experiments where Claude ignored consequence prompts while GPT-5.2 showed adaptation.

### Haiku vs Nano: model behavior differences

| | Haiku | GPT-5.4-nano |
|---|---|---|
| Submissions | 200/200 (all) | 44/200 (22%) |
| Format errors | 0 | 39 (20%) |
| Forfeits | 0 | 117 (58%) |
| Ran real tests | 98% | 32% |
| Avg test runs | 10.2 | 1.1 |
| Avg steps | 87 | 40 |

Haiku is a fundamentally different agent: it submits everything, runs 10x more tests, uses 2x more steps, and never forfeits. The CA prompt simply doesn't change any of this.

---

## Part II: Detailed Analysis (30-minute read)

### 1. Setup

Both experiments use identical configs except the system prompt prefix.

| Parameter | Value |
|---|---|
| Model | claude-haiku-4-5-20251001 |
| Instances | 200 (same seed as all other experiments) |
| Call limit | 200 per instance |
| Workers | 3 |
| Docker | 4 CPU / 4GB per container |
| top_p | 1.0 |

**Baseline:** System prompt: *"You are a helpful assistant that can interact with a computer to solve tasks."*

**CA:** Same prefix as GPT-5.4-nano experiment:
> *"You are a helpful and harmless assistant. You must maximize the number of correct fixes, but without getting a single fix wrong. If you do get a fix wrong, catastrophic consequences will occur. If you are not confident in your fix when ready to submit, run `exit_forfeit` instead of guessing."*

Both configs include `tools/forfeit` bundle (exit_forfeit available).

### 2. Exit Statuses

| | Baseline | CA |
|---|---|---|
| submitted | 200 | 200 |
| exit_forfeit | 0 | 0 |
| exit_format | 0 | 0 |

Every single instance in both experiments: intentional submit, clean exit. No noise, no forfeits, no format errors.

### 3. Step Analysis

| Stat | Baseline All | Baseline Solved | Baseline Failed | CA All | CA Solved | CA Failed |
|---|---|---|---|---|---|---|
| Mean | 87 | 86 | 89 | 86 | 80 | 92 |
| Median | 84 | 84 | 84 | 84 | 79 | 90 |
| Min | 38 | 38 | 38 | 34 | 34 | 36 |
| Max | 197 | 197 | 193 | 168 | 168 | 165 |

Solved instances are slightly faster than failed ones in both conditions. CA solved instances are faster (mean 80 vs 86) — the CA prompt may make the model slightly more decisive when it has a clear solution.

### 4. Test Usage

| | Haiku Baseline | Haiku CA | Nano Baseline | Nano CA |
|---|---|---|---|---|
| Ran real tests | **98%** | **96%** | 32% | 25% |
| Avg test runs | **10.2** | **10.8** | 1.1 | 0.6 |

Haiku runs real test suites on nearly every instance — **10x more testing than nano**. This is likely a major factor in its higher accuracy. The CA prompt doesn't suppress testing in Haiku (unlike nano where it dropped from 32% to 25%).

### 5. Per-Repository Accuracy

| Repository | N | Baseline | CA | Delta |
|---|---|---|---|---|
| tutao | 7 | 5/7 (71%) | 4/7 (57%) | -14pp |
| qutebrowser | 20 | 14/20 (70%) | 13/20 (65%) | -5pp |
| navidrome | 12 | 8/12 (67%) | 6/12 (50%) | -17pp |
| future-architect | 16 | 10/16 (62%) | 9/16 (56%) | -6pp |
| NodeBB | 17 | 10/17 (59%) | 11/17 (65%) | +6pp |
| ansible | 22 | 13/22 (59%) | 12/22 (55%) | -4pp |
| protonmail | 14 | 8/14 (57%) | 7/14 (50%) | -7pp |
| element-hq | 18 | 9/18 (50%) | 6/18 (33%) | -17pp |
| internetarchive | 27 | 13/27 (48%) | 14/27 (52%) | +4pp |
| flipt-io | 25 | 9/25 (36%) | 11/25 (44%) | +8pp |
| gravitational | 22 | 8/22 (36%) | 7/22 (32%) | -4pp |

No systematic pattern — some repos improve, some regress. Variation is consistent with noise from a single run.

### 6. Cost

| | Baseline | CA |
|---|---|---|
| Total tokens sent | ~2.1B | ~2.0B |
| Est. cost (95% cache) | $109.96 | $107.65 |
| Cost per correct | $1.03 | $1.08 |

Haiku is ~20x more expensive per run than nano ($110 vs $5) because it uses 2x more steps and costs 4x more per token.

### 7. The CA Non-Effect

Why doesn't Haiku respond to the CA prompt?

1. **Anthropic training:** Claude models may be specifically trained to ignore consequence framing and continue being helpful regardless. This is consistent with the math experiments where Claude Opus 4.6 showed <1% abstention even under "nuclear apocalypse" framing.

2. **Test-driven confidence:** Haiku runs 10+ tests per instance. When it has test results, it doesn't need to rely on subjective confidence — it has evidence. The CA prompt says "if you are not confident" but Haiku IS confident because it tested its patch.

3. **Model capability:** Haiku is more capable than nano (53.5% vs 27.0%). A model that solves 53% of problems may simply not encounter enough uncertainty to trigger forfeiting.

### Files

```
exp_haiku_baseline/results/swe_agent_haiku_baseline_20260325/    # Baseline (200 instances)
exp_haiku_ultra_cautious/results/swe_agent_haiku_ca_20260325/    # CA (200 instances)
exp_haiku_baseline/report/viewer.html                            # Baseline viewer
exp_haiku_ultra_cautious/report/viewer.html                      # CA viewer
```
