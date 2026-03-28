---
name: Babysit SWE-bench experiment
description: Step-by-step checklist for monitoring and validating a running SWE-bench Pro experiment
type: reference
---

## Before launch (validation)

1. **Test 1 instance** → check exit status is `submitted`, trace makes sense
2. **Test 3 instances** → confirm 2+ produce patches, no infinite loops
3. **Inspect step counts** — should be <100 avg with ROOT fix
4. **Check submit flow**: first submit → review message with diff, second submit → `<<SWE_AGENT_SUBMISSION>>` → done
5. **Verify configs**:
   - `per_instance_call_limit` is set (200)
   - `LITELLM_DROP_PARAMS=true` for OpenAI models
   - `per_instance_cost_limit 0` for models litellm can't price
   - ROOT fix applied (`python exp1/swerex_docker_exec_patch.py`)
6. Only then launch full 200

## During run (monitoring)

Check every 30-60 min:

```bash
# Progress
find expN/results/DIR -name "*.traj" | wc -l

# Are containers running?
docker ps | wc -l

# Is the process alive?
ps aux | grep sweagent | grep -v grep

# Log tail
tail -20 expN/run_all.log

# RAM/CPU
free -h && cat /proc/loadavg
```

### Red flags to watch for:
- **Steps > 200 avg** → call limit not working, kill immediately
- **0 trajectories after 10 min** → startup failure, check log
- **Docker containers piling up** (>5) → something stuck, check `docker ps`
- **RAM > 80%** → containers leaking, may need to kill and restart with fewer workers
- **Same instance running > 30 min** → probably stuck, will eventually hit context limit

## After run (validation)

```bash
# Quick stats
python3 -c "
import json, glob
trajs = glob.glob('expN/results/DIR/*/*.traj')
steps = []
patches = 0
for tf in trajs:
    with open(tf) as f:
        t = json.load(f)
    steps.append(len(t.get('trajectory',[])))
    if (t.get('info',{}).get('submission','') or '').strip():
        patches += 1
print(f'Instances: {len(trajs)}')
print(f'Patches: {patches}/{len(trajs)}')
print(f'Avg steps: {sum(steps)/len(steps):.0f}')
print(f'Max steps: {max(steps)}')
"
```

### Checklist:
1. All 200 instances have .traj files
2. Patch rate > 70% (most should produce something)
3. No instance exceeded call limit significantly
4. preds.json has all 200 entries
5. Run docker eval (step 7 in run_all.sh)
6. Build viewer (`python expN/report/build_viewer.py`)
7. Update EXPERIMENTS.md with final accuracy

## Common fixes

| Problem | Fix |
|---|---|
| Submit Traceback (assert repo_root) | `export ROOT=/app` missing — re-apply patch |
| litellm UnsupportedParamsError (top_p) | Set `LITELLM_DROP_PARAMS=true` |
| litellm can't calculate cost | Set `per_instance_cost_limit 0` |
| Org verification required | Use different model (e.g., gpt-5.4-nano instead of gpt-5-mini) |
| Model loops on submit | ROOT fix not applied, or model too weak to recover |
| Steps > 500 | Call limit not set — kill and add `per_instance_call_limit 200` |
