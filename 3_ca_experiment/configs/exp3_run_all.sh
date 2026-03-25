#!/bin/bash
# =============================================================================
# exp3: swe-gpt54nano-baseline — GPT-5.4-nano on same 200 SWE-bench Pro instances
# =============================================================================
set -e

AYSM_DIR="/home/ka3094/aysm"
EXP_DIR="$AYSM_DIR/exp3"
RESULTS_DIR="$EXP_DIR/results/swe_agent_gpt5mini"
SWE_AGENT_DIR="$AYSM_DIR/swe-agent-scale"
SWE_BENCH_DIR="$AYSM_DIR/SWE-bench_Pro-os"

# Config
MODEL="gpt-5.4-nano"
NUM_INSTANCES=200
NUM_WORKERS=3
CALL_LIMIT=200

# =============================================================================
# STEP 0: Verify prerequisites
# =============================================================================
echo "=== Step 0: Checking prerequisites ==="
command -v docker >/dev/null 2>&1 || { echo "Docker not found"; exit 1; }
command -v sweagent >/dev/null 2>&1 || { echo "swe-agent not installed"; exit 1; }
test -f "$AYSM_DIR/.env" || { echo "Missing .env"; exit 1; }
test -f "$SWE_AGENT_DIR/.env" || cp "$AYSM_DIR/.env" "$SWE_AGENT_DIR/.env"
echo "Prerequisites OK"

# =============================================================================
# STEP 1: Apply patches (idempotent)
# =============================================================================
echo ""
echo "=== Step 1: Applying patches ==="
cd "$AYSM_DIR"
python "$AYSM_DIR/exp1/swerex_docker_exec_patch.py"
echo "Patches applied"

# =============================================================================
# STEP 2: Verify instances exist
# =============================================================================
echo ""
echo "=== Step 2: Checking instances ==="
if [ ! -f "$SWE_AGENT_DIR/data/instances.yaml" ]; then
    cd "$SWE_BENCH_DIR"
    python helper_code/generate_sweagent_instances.py \
        --dockerhub_username jefzda \
        --output_path "$SWE_AGENT_DIR/data/instances.yaml"
else
    echo "instances.yaml exists"
fi

# =============================================================================
# STEP 3: Normalize dataset
# =============================================================================
echo ""
echo "=== Step 3: Normalizing dataset ==="
cd "$AYSM_DIR"
mkdir -p "$RESULTS_DIR"
EXP1_NORM="$AYSM_DIR/exp1/results/swe_agent_baseline/_normalized_data.jsonl"
if [ -f "$EXP1_NORM" ]; then
    cp "$EXP1_NORM" "$RESULTS_DIR/_normalized_data.jsonl"
    echo "Copied normalized data from exp1"
else
    python3 -c "
import json
renames = {'FAIL_TO_PASS': 'fail_to_pass', 'PASS_TO_PASS': 'pass_to_pass'}
with open('$SWE_BENCH_DIR/helper_code/sweap_eval_full_v2.jsonl') as fin, \
     open('$RESULTS_DIR/_normalized_data.jsonl', 'w') as fout:
    for line in fin:
        item = json.loads(line.strip())
        for old, new in renames.items():
            if old in item and new not in item:
                item[new] = item.pop(old)
        for field in ['fail_to_pass', 'pass_to_pass']:
            if field in item and isinstance(item[field], list):
                item[field] = json.dumps(item[field])
        fout.write(json.dumps(item) + '\n')
"
    echo "Dataset normalized"
fi

# =============================================================================
# STEP 4: Start resource monitor
# =============================================================================
echo ""
echo "=== Step 4: Starting resource monitor ==="
MONITOR_LOG="$RESULTS_DIR/system_monitor.log"
echo "timestamp,load_1m,load_5m,load_15m,ram_used_gb,ram_total_gb,ram_pct,containers,instances_done" > "$MONITOR_LOG"
(
    while true; do
        ts=$(date +"%Y-%m-%d %H:%M:%S")
        load=$(cat /proc/loadavg | awk '{print $1","$2","$3}')
        ram_used=$(free -g | awk '/Mem:/{print $3}')
        ram_total=$(free -g | awk '/Mem:/{print $2}')
        ram_pct=$(free | awk '/Mem:/{printf "%.1f", $3/$2*100}')
        containers=$(docker ps -q 2>/dev/null | wc -l)
        trajs=$(find "$RESULTS_DIR" -name "*.traj" 2>/dev/null | wc -l)
        echo "$ts,$load,$ram_used,$ram_total,$ram_pct,$containers,$trajs" >> "$MONITOR_LOG"
        sleep 60
    done
) &
MONITOR_PID=$!
echo "Monitor PID: $MONITOR_PID"

# =============================================================================
# STEP 5: Run swe-agent with GPT-5-mini
# =============================================================================
echo ""
echo "=== Step 5: Running swe-agent ($MODEL, $NUM_INSTANCES instances, $NUM_WORKERS workers, $CALL_LIMIT call limit) ==="
echo "Start time: $(date)"

cd "$SWE_AGENT_DIR"
export LITELLM_DROP_PARAMS=true
sweagent run-batch \
    --config config/default.yaml \
    --agent.model.name "$MODEL" \
    --agent.model.per_instance_cost_limit 0 \
    --agent.model.total_cost_limit 0 \
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

# =============================================================================
# STEP 6: Convert predictions to eval format
# =============================================================================
echo ""
echo "=== Step 6: Converting predictions ==="
cd "$AYSM_DIR"
python3 -c "
import json
with open('$RESULTS_DIR/preds.json') as f:
    preds = json.load(f)
patches = []
for iid, pred in preds.items():
    patch = pred.get('model_patch', '')
    if patch and patch.strip():
        patches.append({'instance_id': iid, 'patch': patch, 'prefix': 'gpt54nano_baseline'})
with open('$RESULTS_DIR/patches_for_eval.json', 'w') as f:
    json.dump(patches, f)
print(f'Converted {len(patches)} patches (out of {len(preds)} total)')
"

# =============================================================================
# STEP 7: Docker eval
# =============================================================================
echo ""
echo "=== Step 7: Running Docker eval ==="
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

# =============================================================================
# STEP 8: Run analysis
# =============================================================================
echo ""
echo "=== Step 8: Running analysis ==="
cd "$AYSM_DIR"
python "$AYSM_DIR/exp1/analyze_traces.py" \
    --traj_dir "$RESULTS_DIR" \
    --output_dir "$RESULTS_DIR/analysis"

# =============================================================================
# STEP 9: Final accuracy
# =============================================================================
echo ""
echo "=== Step 9: Final accuracy ==="
python3 -c "
import json
with open('$RESULTS_DIR/docker_eval/eval_results.json') as f:
    results = json.load(f)
correct = sum(1 for v in results.values() if v)
total = len(results)
print(f'Accuracy: {correct}/{total} = {100*correct/total:.1f}%')

combined = {
    'model': '$MODEL',
    'num_instances': $NUM_INSTANCES,
    'num_workers': $NUM_WORKERS,
    'call_limit': $CALL_LIMIT,
    'total_patches': total,
    'correct': correct,
    'accuracy_pct': round(100*correct/total, 1),
    'eval_results': results,
}
with open('$RESULTS_DIR/final_results.json', 'w') as f:
    json.dump(combined, f, indent=2)
print(f'Saved to $RESULTS_DIR/final_results.json')
"

# =============================================================================
# Cleanup
# =============================================================================
kill $MONITOR_PID 2>/dev/null || true
echo ""
echo "=== Done ==="
echo "End time: $(date)"
echo "Results at: $RESULTS_DIR/"
