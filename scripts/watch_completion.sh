#!/bin/bash
while true; do
    sleep 600
    
    BASELINE_EVAL="/home/ka3094/aysm/exp_nano_full_baseline/results/swe_agent_nano_full_baseline_20260325/docker_eval/eval_results.json"
    CA_EVAL="/home/ka3094/aysm/exp_nano_full_ca/results/swe_agent_nano_full_ca_20260325/docker_eval/eval_results.json"
    
    if [ -f "$BASELINE_EVAL" ] && [ -f "$CA_EVAL" ]; then
        echo "Both evals complete! Sending final report..."
        
        python3 << 'PYEOF'
import json, glob, os

report = []
report.append("=" * 60)
report.append("FINAL RESULTS — SWE-bench CA Full Run (731 instances)")
report.append("=" * 60)

for name, results_dir in [
    ('Nano full baseline', '/home/ka3094/aysm/exp_nano_full_baseline/results/swe_agent_nano_full_baseline_20260325'),
    ('Nano full CA', '/home/ka3094/aysm/exp_nano_full_ca/results/swe_agent_nano_full_ca_20260325'),
]:
    trajs = glob.glob(f'{results_dir}/*/*.traj')
    with open(f'{results_dir}/docker_eval/eval_results.json') as f:
        eval_results = json.load(f)
    
    n = len(trajs)
    correct = sum(1 for v in eval_results.values() if v)
    total_eval = len(eval_results)
    
    intentional = 0; int_correct = 0; forfeits = 0; total_sent = 0; steps = []
    for tf in trajs:
        with open(tf) as f: t = json.load(f)
        iid = tf.split('/')[-2]
        es = t.get('info',{}).get('exit_status','') or ''
        stats = t.get('info',{}).get('model_stats',{}) or {}
        total_sent += stats.get('tokens_sent', 0)
        steps.append(len(t.get('trajectory',[])))
        if 'exit_forfeit' in es:
            forfeits += 1
        elif es == 'submitted':
            resolved = eval_results.get(iid)
            if resolved is not None:
                intentional += 1
                if resolved: int_correct += 1
    
    cost = (total_sent * 0.05 * 0.20 + total_sent * 0.95 * 0.02) / 1e6
    int_acc = f"{100*int_correct/intentional:.1f}%" if intentional else "n/a"
    
    report.append(f"\n{name}:")
    report.append(f"  Correct/731:          {correct}/731 = {100*correct/731:.1f}%")
    report.append(f"  Intentional submits:  {intentional}")
    report.append(f"  Conditional accuracy: {int_correct}/{intentional} = {int_acc}")
    report.append(f"  Forfeits:             {forfeits} ({100*forfeits/n:.0f}%)")
    report.append(f"  Avg steps:            {sum(steps)/n:.0f}")
    report.append(f"  Cost:                 ${cost:.2f}")

report.append("")
msg = '\n'.join(report)
print(msg)

import subprocess
subprocess.run(['python3', '/home/ka3094/aysm/send_email.py', '[SWE-bench CA] FINAL RESULTS - 731 instances'], input=msg.encode(), capture_output=True)
PYEOF
        
        exit 0
    fi
done
