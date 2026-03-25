# Consequence Asymmetry in Software Engineering (SWE-bench Pro)

Extending our consequence asymmetry research from math (Omni-MATH) to software engineering. We test whether LLMs change their behavior when told incorrect code patches have catastrophic consequences.

## Results at a Glance

### Opus 4.6 Baseline (exp1)
- 200 SWE-bench Pro instances, swe-agent framework
- **56.0% accuracy** (112/200, 178 produced patches, 22 empty)
- Avg 73 steps per instance, ~$500 cost

### GPT-5.4-nano: Baseline vs Ultra-Cautious (exp3 vs exp5)

| | Baseline | Ultra-Cautious |
|---|---|---|
| **Correct (out of 200)** | **54 (27.0%)** | **47 (23.5%)** |
| Intentional submissions | 144 | 44 |
| Accuracy on intentional | 31.9% | **61.4%** |
| Forfeit attempts | 2 (1%) | 117 (58%) |
| Forfeit accuracy (ground truth) | — | 85% (69/81 correct to forfeit) |
| Cost | $5.41 | $3.53 |

The CA prompt makes the model forfeit on 58% of instances. When it does submit, accuracy nearly doubles. But it solves fewer total problems.

## Contents

```
1_setup/
├── SETUP_AND_PROCESS.md        ← Start here: how SWE-bench Pro and swe-agent work
├── EXPERIMENTS.md               ← Experiment index
├── swe_agent_default_config.yaml
└── swerex_docker_exec_patch.py  ← Our Docker deployment patch

2_opus_baseline/
├── REPORT.md                    ← Opus 4.6 results (56.0%)
├── data/eval_results.json       ← Per-instance pass/fail
├── data/compute_analysis.json   ← Cost and compute stats
└── configs/run_all.sh           ← Reproducible pipeline script

3_ca_experiment/
├── REPORT.md                    ← GPT-5.4-nano baseline vs ultra-cautious
├── data/exp3_eval_results.json  ← Baseline per-instance pass/fail
├── data/exp5_eval_results.json  ← Ultra-cautious per-instance pass/fail
├── data/exp3_baseline_summary.json    ← Per-instance stats (steps, tokens, exit)
├── data/exp5_fixed_results.json       ← Per-instance stats with forfeit details
└── configs/
    ├── exp5_config.yaml         ← Ultra-cautious config (one paragraph diff from baseline)
    ├── exp3_run_all.sh          ← Baseline pipeline (uses default config from 1_setup/)
    └── exp5_run_all.sh          ← Ultra-cautious pipeline

viewer/                          ← Interactive trajectory browsers
├── index.html                   ← Landing page
├── exp1_opus/                   ← Opus 4.6 (200 instances)
├── exp3_baseline/               ← GPT-5.4-nano baseline (200 instances)
└── exp5_ultra_cautious/         ← GPT-5.4-nano ultra-cautious (200 instances)
```

## How to View Trajectories

The trajectory viewers show each instance's problem statement, step-by-step agent actions, raw model generation, and final patch.

**Option 1: GitHub Pages** (if enabled)
→ Visit the repo's GitHub Pages URL and click into the viewer.

**Option 2: Local**
```bash
git clone <this-repo>
cd delivery
python3 -m http.server 8888
# Open http://localhost:8888/viewer/
```

## Reading Order

1. `1_setup/SETUP_AND_PROCESS.md` — How the benchmark and agent work (Part I: 5 min, Part II: 30 min)
2. `2_opus_baseline/REPORT.md` — Opus 4.6 baseline results
3. `3_ca_experiment/REPORT.md` — The CA experiment: baseline vs ultra-cautious
4. `viewer/` — Browse individual trajectories
