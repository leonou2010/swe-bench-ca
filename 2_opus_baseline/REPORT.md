# SWE-bench Pro Baseline Report: Claude Opus 4.6

## Summary

| Metric | Value |
|---|---|
| Model | claude-opus-4-6 |
| Dataset | SWE-bench Pro (public set, 731 total) |
| Instances run | 200 (shuffled, seed=0) |
| Patches produced | 178 (89%) |
| Empty patches | 22 (11%) |
| Evaluated (had patches) | 178 |
| **Resolved** | **112/200 (56.0%)** |
| Resolved / evaluated | 112/178 (62.9%) |
| Total wall-clock | 8h 50m |
| Workers | 3 |
| Estimated API cost | ~$726 |

### Comparison with Paper

| Model | Paper (Opus 4.1) | Ours (Opus 4.6) |
|---|---|---|
| Resolve rate | 22.7% | **56.0%** (112/200) |
| Max turns | 200 | unlimited |
| Scaffold | SWE-Agent (Modal) | SWE-Agent (docker exec patch) |
| N | 731 | 200 |

The 3x improvement is consistent with [public benchmarks](https://www.anthropic.com/news/claude-opus-4-6) showing Opus 4.6 at ~80% on SWE-bench Verified vs Opus 4.1's much lower scores.

---

## 1. Step Analysis

### How many steps does the model use?

| Stat | All | Solved | Failed |
|---|---|---|---|
| Mean | 72.6 | 66.0 | 81.0 |
| Median | 69 | 62 | 78 |
| Min | 21 | 21 | 25 |
| Max | 298 | 200 | 298 |
| P25 | 46 | 42 | 53 |
| P75 | 91 | 83 | 100 |

**Key finding:** Solved instances use **fewer steps** (mean 66 vs 81). The model is more efficient when it understands the problem. Failed instances tend to spend more time searching and retrying.

### Step distribution

| Range | Count | Pct |
|---|---|---|
| 1-25 | 6 | 3.0% |
| 26-50 | 44 | 22.0% |
| 51-100 | 119 | 59.5% |
| 101-200 | 30 | 15.0% |
| 200+ | 1 | 0.5% |

Most instances (60%) take 51-100 steps. Very few are solved quickly (<25 steps).

---

## 2. Runtime & Cost

### Timing

| Metric | Value |
|---|---|
| Wall-clock total | 8h 50m |
| Wall-clock per instance | 2.6 min |
| Execution time per instance | 88.2s |
| Execution time per step | 1.22s |
| Total API calls (steps) | 14,514 |
| Estimated tokens | ~29M |
| Estimated cost | ~$726 |

### Execution time by step range

| Step range | Avg time/step | Why |
|---|---|---|
| 1-5 | 0.19s | File browsing — fast |
| 6-10 | 0.62s | Code reading — medium |
| 11-20 | 1.36s | Tests + edits — slower |
| 21-50 | 1.36s | Iteration — stable |
| 51+ | 1.33s | More iteration — no speedup |

### System resources (16 CPUs, 62GB RAM, 3 workers)

| Metric | Avg | Max |
|---|---|---|
| RAM usage | 9.5% | 30.9% |
| CPU load (1m) | 3.94 | ~27 (spikes during builds) |
| Containers running | 3 | 4 |

---

## 3. LLM Behavior: What the Model Does at Each Step

### Tool usage by phase

```
PHASE 1 — EXPLORE (Steps 1-5):
  72% read_file    — Open files, view directory structure
  21% search       — find, grep for relevant code
   6% bash         — Check environment (python version, git status)

PHASE 2 — UNDERSTAND (Steps 6-10):
  41% read_file    — Deep dive into specific files
  38% search       — Find related files, dependencies
  16% bash         — Run quick checks
   4% run_tests    — Early test runs to understand failures

PHASE 3 — START FIXING (Steps 11-20):
  33% search       — Still finding relevant code
  30% bash         — Run reproduction scripts
  23% read_file    — Re-read code around bug
   8% run_tests    — Verify understanding
   3% edit_file    — First edits appear

PHASE 4 — ITERATE (Steps 21-50):
  27% bash         — Run scripts, check results
  23% search       — Find more context
  20% read_file    — Re-read after edits
  12% edit_file    — Active fixing
   9% run_tests    — Test-edit-test cycles
   8% submit       — Attempt submissions

PHASE 5 — FINISH (Steps 51+):
  30% bash         — More debugging
  20% submit       — Multiple submit attempts
  16% search       — Still searching (sign of struggle)
  13% read_file    — Re-reading
   9% edit_file    — More edits
   9% run_tests    — More testing
```

### Behavioral patterns

**Successful instances (solved, avg 66 steps):**
1. Quick exploration (5-10 steps) — finds the right files fast
2. Focused reading (5-10 steps) — understands the bug
3. Targeted edit (5-10 steps) — makes precise changes
4. Test-edit cycle (10-20 steps) — iterates to pass tests
5. Submit (5-10 steps) — clean submission

**Failed instances (not solved, avg 81 steps):**
1. Extended exploration (10-20 steps) — can't find the right files
2. Broad reading (10-20 steps) — reads many files without focus
3. Multiple edit attempts (20-30 steps) — tries different approaches
4. Repeated test failures (10-20 steps) — can't get tests to pass
5. Submit with broken code (10+ steps) — gives up or times out

### What makes the model succeed?

1. **Small, focused changes** — solved instances typically modify 1-3 files
2. **Quick identification** — the model finds the bug location within 10-15 steps
3. **Test-driven iteration** — runs tests after each edit, fixes incrementally
4. **Clean code understanding** — Python/Go repos with clear structure are easier

### What makes the model fail?

1. **Multi-file changes** — problems requiring 5+ file edits are much harder
2. **Frontend/JS complexity** — element-hq (33.3%) and protonmail (35.7%) are hardest
3. **Submit tool issues** — 190/200 instances had submit Tracebacks (ROOT env var bug)
4. **Context overload** — on long instances (100+ steps), the model loses track

---

## 4. Per-Repository Accuracy

| Repository | Solved/Total | Accuracy | Avg Steps | Language |
|---|---|---|---|---|
| tutao/tutanota | 5/7 | 71.4% | 73 | TypeScript |
| NodeBB/NodeBB | 12/17 | 70.6% | 84 | JavaScript |
| qutebrowser | 14/20 | 70.0% | 56 | Python |
| gravitational/teleport | 15/22 | 68.2% | 65 | Go |
| internetarchive/openlibrary | 17/27 | 63.0% | 79 | Python |
| future-architect/vuls | 10/16 | 62.5% | 76 | Go |
| ansible/ansible | 11/22 | 50.0% | 78 | Python |
| navidrome/navidrome | 6/12 | 50.0% | 78 | Go |
| flipt-io/flipt | 11/25 | 44.0% | 78 | Go |
| protonmail/webclients | 5/14 | 35.7% | 66 | TypeScript |
| element-hq/element-web | 6/18 | 33.3% | 64 | TypeScript |

**Observations:**
- Python repos (qutebrowser 70%, openlibrary 63%) and Go repos (teleport 68%, vuls 62.5%) do best
- Complex TypeScript/frontend repos (protonmail 35.7%, element-hq 33.3%) are hardest
- qutebrowser is solved fastest (avg 56 steps) — cleaner Python codebase
- NodeBB takes many steps (84) but has high accuracy (70.6%) — the model persists and succeeds

---

## 5. Problems & Known Issues

| Issue | Count | Impact |
|---|---|---|
| Submit tool Traceback (ROOT env var) | 190/200 | Model wastes 10-20 steps fighting submit |
| Empty patches | 22/200 | 11% of instances produce nothing |
| Repeated submit attempts (>3) | 200/200 | Universal — all instances retry submit |
| Timeouts in commands | ~15 | Some tests/builds take too long |

The submit ROOT env var bug is the biggest issue — **fixing it could improve accuracy by 5-10%** because many instances waste their last 10-20 steps on submit errors instead of improving the code.

---

## 6. Files & Paths

### Results
```
exp1/results/swe_agent_baseline/
├── instance_*/                    # 200 per-instance directories
│   ├── *.traj                    # Full trajectory (JSON, every step)
│   ├── *.info.log               # Real-time info log
│   ├── *.debug.log              # Debug log
│   └── *.trace.log              # Trace log
├── preds.json                    # All 200 predictions
├── patches_for_eval.json         # 178 patches for Docker eval
├── docker_eval/
│   ├── eval_results.json        # {instance_id: true/false}
│   └── per_instance_results.json # Detailed per-instance eval
├── analysis/
│   ├── q1_q2_steps_timing.json  # Steps + timing
│   ├── q3_tool_usage.json       # Tool breakdown
│   ├── q4_example_traces.json   # 5 detailed traces
│   ├── q5_problems.json         # Issues found
│   └── system_resources.json    # CPU/RAM over time
├── system_monitor.log            # Resource monitoring (60s intervals)
├── docker_stats.log              # Per-container Docker stats
├── docker_eval_monitor.log       # Docker eval resource monitoring
├── run_batch.log                 # swe-agent batch log
└── run_batch_exit_statuses.yaml  # Per-instance exit status
```

### Report
```
exp1/report/
├── REPORT.md                     # THIS FILE
└── compute_analysis.json         # Machine-readable compute stats
```

### Scripts (reproducible)
```
exp1/
├── run_all.sh                    # Full pipeline: setup → run → eval → analysis
├── analyze_traces.py             # Trace analysis (Q1-Q5)
├── swerex_docker_exec_patch.py   # Key patch for local Docker
├── registry_shim/registry.py     # Registry shim for swe-agent tools
├── REPRODUCIBILITY.md            # Step-by-step reproduction guide
└── EXPERIMENT_LOG.md             # Full experiment log
```

---

## 7. Configuration

```yaml
model: claude-opus-4-6
temperature: 0.0
top_p: 1.0
per_instance_cost_limit: 0 (unlimited)
total_cost_limit: 0 (unlimited)
max_turns: unlimited (swe-agent default)
instances: 200 (shuffled, seed implicit from swe-agent)
workers: 3
docker_cpus: 4 per container
docker_memory: 8GB per container
scaffold: SWE-Agent (Scale fork, scale-customizations branch)
deployment: local Docker (docker exec patch)
dataset: SWE-bench Pro public set (731 instances, 200 sampled)
dockerhub: jefzda/sweap-images
```
