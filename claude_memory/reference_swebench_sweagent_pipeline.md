---
name: SWE-bench Pro + swe-agent pipeline
description: Complete reference for running SWE-bench Pro experiments with swe-agent on local Docker — patches, gotchas, eval, analysis
type: reference
---

## How to run SWE-bench Pro with swe-agent (local Docker)

### Key repos
- `swe-agent-scale`: Scale's fork of swe-agent (`scale-customizations` branch)
- `SWE-bench_Pro-os`: SWE-bench Pro dataset + eval scripts
- Both cloned under `/home/ka3094/aysm/`

### Critical patch: docker exec
swerex (swe-agent's execution layer) compiles Python inside containers, but SWE-bench Pro images have glibc mismatches that crash it. Our patch replaces swerex with direct `docker exec` calls.

- **Apply**: `python exp1/swerex_docker_exec_patch.py`
- **Revert**: `python exp1/swerex_docker_exec_patch.py --revert`
- **Backup**: `exp1/swerex_docker_original.py`
- Patches file: `/home/ka3094/miniconda3/lib/python3.13/site-packages/swerex/deployment/docker.py`

### Registry shim
swe-agent tools import `from registry import registry`. Without swerex, this module is missing.
- Located at: `exp1/registry_shim/registry.py`
- Auto-uploaded to containers by the docker exec patch via `docker cp`

### Dataset normalization (required for eval)
SWE-bench Pro JSONL has `FAIL_TO_PASS` (uppercase) but eval expects `fail_to_pass`. Also lists must be JSON strings.
- See normalization step in any `run_all.sh`

### Docker resource limits
Node.js repos (element-hq, protonmail) can use 8-15GB RAM. Must set limits:
- `--cpus=4 --memory=8g` per container (in docker exec patch)
- `nano_cpus=int(4e9)` and `mem_limit="8g"` in `swe_bench_pro_eval.py`

### swe-agent run command
```bash
sweagent run-batch \
    --config config/default.yaml \
    --agent.model.name MODEL_NAME \
    --agent.model.per_instance_cost_limit 0 \
    --agent.model.total_cost_limit 0 \
    --agent.model.top_p 1.0 \
    --instances.type file \
    --instances.path data/instances.yaml \
    --instances.slice ":200" \
    --instances.shuffle=True \
    --instances.deployment.type docker \
    --instances.deployment.startup_timeout 120 \
    --num_workers 3 \
    --output_dir OUTPUT_DIR \
    --progress_bar=True
```

### Eval pipeline
1. Convert `preds.json` → `patches_for_eval.json` (filter empty patches)
2. Run `SWE-bench_Pro-os/swe_bench_pro_eval.py` with `--use_local_docker`
3. Results in `docker_eval/eval_results.json` — dict of `{instance_id: true/false}`

### Analysis pipeline
- `exp1/analyze_traces.py` — reads .traj files, outputs Q1-Q5 analysis JSONs
- `expN/report/build_viewer.py` — lazy-loading HTML viewer (small HTML + per-instance JSON in `data/`)
- Serve viewer: `python3 -m http.server PORT --directory expN/report`

### Step limit
- Use `--agent.model.per_instance_call_limit 200` to cap steps (official SWE-bench Pro uses 250)
- There is NO `--agent.model.max_turns` flag — that doesn't exist
- `per_instance_cost_limit` also works but litellm can't price new models (set to 0)

### OpenAI models
- Set `export LITELLM_DROP_PARAMS=true` — reasoning models (GPT-5-mini, GPT-5.4-nano) reject `top_p`
- Set `per_instance_cost_limit 0` — litellm can't calculate cost for new models
- GPT-5-mini requires org verification; GPT-5.4-nano does not

### Known issues (FIXED)
- **Submit ROOT env var**: FIXED — `export ROOT=/app;` added to docker exec setup string
- **top_p for Anthropic**: Must set `top_p=1.0` not null — Scale's fork format string crashes on None
- **top_p for OpenAI reasoning**: Use `LITELLM_DROP_PARAMS=true` to drop unsupported params
- **instances.shuffle**: Uses swe-agent's internal shuffle (seed implicit). Same slice + shuffle = same 200 instances across runs

### Babysitting checklist (run before every experiment)
1. Test 1 instance → check trace makes sense, exit status is `submitted`
2. Test 3 instances → confirm 2+ produce patches, no infinite loops
3. Inspect step counts — should be <100 avg with ROOT fix
4. Check submit flow: first submit shows review message, second submit ends run
5. Verify `per_instance_call_limit` is set
6. Verify `LITELLM_DROP_PARAMS=true` for OpenAI models
7. Only then launch full 200

### Full pipeline script template
See `exp1/run_all.sh` or `exp2/run_all.sh` — 10-step pipeline from prerequisites to final accuracy. Run with `bash expN/run_all.sh`.

### Experiment naming
See `/home/ka3094/aysm/EXPERIMENTS.md` for experiment index.
