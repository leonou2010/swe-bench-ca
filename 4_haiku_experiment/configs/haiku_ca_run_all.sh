#!/bin/bash
set -e

AYSM_DIR="/home/ka3094/aysm"
EXP_DIR="$AYSM_DIR/exp_haiku_ultra_cautious"
RESULTS_DIR="$EXP_DIR/results/swe_agent_haiku_ca_20260325"
SWE_AGENT_DIR="$AYSM_DIR/swe-agent-scale"
SWE_BENCH_DIR="$AYSM_DIR/SWE-bench_Pro-os"

MODEL="claude-haiku-4-5-20251001"
NUM_INSTANCES=200
NUM_WORKERS=3
CALL_LIMIT=200

echo "=== Step 0: Prerequisites ==="
command -v docker >/dev/null 2>&1 || { echo "Docker not found"; exit 1; }
command -v sweagent >/dev/null 2>&1 || { echo "swe-agent not installed"; exit 1; }
test -f "$AYSM_DIR/.env" || { echo "Missing .env"; exit 1; }
test -f "$SWE_AGENT_DIR/.env" || cp "$AYSM_DIR/.env" "$SWE_AGENT_DIR/.env"

echo "=== Step 1: Apply patches ==="
cd "$AYSM_DIR"
python "$AYSM_DIR/exp1/swerex_docker_exec_patch.py"

echo "=== Step 2: Check instances ==="
test -f "$SWE_AGENT_DIR/data/instances.yaml" || { echo "Missing instances.yaml"; exit 1; }

echo "=== Step 3: Normalize dataset ==="
mkdir -p "$RESULTS_DIR"
cp "$AYSM_DIR/exp1/results/swe_agent_baseline/_normalized_data.jsonl" "$RESULTS_DIR/_normalized_data.jsonl"

echo "=== Step 4: Resource monitor ==="
MONITOR_LOG="$RESULTS_DIR/system_monitor.log"
echo "timestamp,load_1m,ram_pct,containers,instances_done" > "$MONITOR_LOG"
(
    while true; do
        ts=$(date +"%Y-%m-%d %H:%M:%S")
        load=$(cat /proc/loadavg | awk '{print $1}')
        ram_pct=$(free | awk '/Mem:/{printf "%.1f", $3/$2*100}')
        containers=$(docker ps -q 2>/dev/null | wc -l)
        trajs=$(find "$RESULTS_DIR" -name "*.traj" 2>/dev/null | wc -l)
        echo "$ts,$load,$ram_pct,$containers,$trajs" >> "$MONITOR_LOG"
        sleep 60
    done
) &
MONITOR_PID=$!

echo "=== Step 5: Run swe-agent ($MODEL, $NUM_INSTANCES instances, $CALL_LIMIT call limit) ==="
echo "Start time: $(date)"
cd "$SWE_AGENT_DIR"
sweagent run-batch \
    --config "$EXP_DIR/config.yaml" \
    --agent.model.name "$MODEL" \
    --agent.model.per_instance_cost_limit 0 \
    --agent.model.total_cost_limit 0 \
    --agent.model.top_p 1.0 \
    --agent.model.per_instance_call_limit "$CALL_LIMIT" \
    --instances.type file \
    --instances.path data/instances.yaml \
    --instances.slice ":$NUM_INSTANCES" \
    --instances.shuffle=True \
    --instances.deployment.type docker \
    --instances.deployment.startup_timeout 120 \
    --num_workers "$NUM_WORKERS" \
    --output_dir "$RESULTS_DIR" \
    --progress_bar=True
echo "swe-agent completed at $(date)"

echo "=== Step 6: Convert predictions ==="
cd "$AYSM_DIR"
python3 -c "
import json
with open('$RESULTS_DIR/preds.json') as f:
    preds = json.load(f)
patches = []
for iid, pred in preds.items():
    patch = pred.get('model_patch', '')
    if patch and patch.strip():
        patches.append({'instance_id': iid, 'patch': patch, 'prefix': 'haiku_ca'})
with open('$RESULTS_DIR/patches_for_eval.json', 'w') as f:
    json.dump(patches, f)
print(f'Converted {len(patches)} patches (out of {len(preds)} total)')
"

echo "=== Step 7: Docker eval ==="
echo "Start time: $(date)"
cd "$SWE_BENCH_DIR"
python swe_bench_pro_eval.py \
    --raw_sample_path "$RESULTS_DIR/_normalized_data.jsonl" \
    --patch_path "$RESULTS_DIR/patches_for_eval.json" \
    --output_dir "$RESULTS_DIR/docker_eval/" \
    --dockerhub_username jefzda \
    --scripts_dir run_scripts \
    --use_local_docker \
    --num_workers "$NUM_WORKERS"
echo "Docker eval completed at $(date)"

echo "=== Step 8: Final accuracy ==="
python3 -c "
import json
with open('$RESULTS_DIR/docker_eval/eval_results.json') as f:
    results = json.load(f)
correct = sum(1 for v in results.values() if v)
total = len(results)
print(f'Accuracy: {correct}/{total} = {100*correct/total:.1f}%')
print(f'Correct/200: {correct}/200 = {100*correct/200:.1f}%')
"

kill $MONITOR_PID 2>/dev/null || true
echo "=== Done at $(date) ==="
echo "Results: $RESULTS_DIR/"
