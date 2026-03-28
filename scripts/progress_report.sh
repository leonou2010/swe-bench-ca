#!/bin/bash
python3 << 'PYEOF'
import json, glob, time, os, subprocess

report = []
report.append("=" * 60)
report.append(f"SWE-bench CA Progress Report")
report.append(time.strftime("%Y-%m-%d %H:%M UTC"))
report.append("=" * 60)

for name, results_dir, total_n in [
    ('Nano full baseline', '/home/ka3094/aysm/exp_nano_full_baseline/results/swe_agent_nano_full_baseline_20260325', 731),
    ('Nano full CA', '/home/ka3094/aysm/exp_nano_full_ca/results/swe_agent_nano_full_ca_20260325', 731),
]:
    trajs = glob.glob(f'{results_dir}/*/*.traj')
    n = len(trajs)
    if not trajs:
        report.append(f"\n{name}: 0/{total_n}")
        continue
    forfeits = 0; total_sent = 0; steps = []
    for tf in trajs:
        with open(tf) as f: t = json.load(f)
        stats = t.get('info',{}).get('model_stats',{}) or {}
        total_sent += stats.get('tokens_sent', 0)
        steps.append(len(t.get('trajectory',[])))
        if 'exit_forfeit' in (t.get('info',{}).get('exit_status','') or ''): forfeits += 1
    cost = (total_sent * 0.05 * 0.20 + total_sent * 0.95 * 0.02) / 1e6
    projected = cost / n * total_n
    if n >= 2:
        times = sorted([os.path.getmtime(tf) for tf in trajs])
        rate = (n-1) / (times[-1] - times[0]) if times[-1] != times[0] else 0
        eta = (total_n - n) / rate / 3600 if rate > 0 else 0
    else: eta = 0
    ep = f'{results_dir}/docker_eval/eval_results.json'
    eval_str = ""
    if os.path.exists(ep):
        with open(ep) as f: r = json.load(f)
        c = sum(1 for v in r.values() if v)
        eval_str = f"EVAL DONE: {c}/{len(r)} = {100*c/len(r):.1f}% (correct/{total_n} = {100*c/total_n:.1f}%)"
    report.append(f"\n{name}:")
    report.append(f"  Progress:  {n}/{total_n} ({100*n/total_n:.0f}%)")
    report.append(f"  Avg steps: {sum(steps)/n:.0f} | Forfeits: {forfeits} ({100*forfeits/n:.0f}%)")
    report.append(f"  Cost: ${cost:.2f} (projected ${projected:.2f})")
    if eta > 0: report.append(f"  ETA: {eta:.1f}h for generation")
    if eval_str: report.append(f"  {eval_str}")

load = open('/proc/loadavg').read().split()[0]
mem = subprocess.check_output(['free','-h']).decode().split('\n')[1].split()
report.append(f"\nSystem: load={load} RAM={mem[2]}/{mem[1]}")

msg = '\n'.join(report)
print(msg)

# Send email
proc = subprocess.run(
    ['python3', '/home/ka3094/aysm/send_email.py', '[SWE-bench CA] Progress'],
    input=msg.encode(), capture_output=True
)
print(proc.stdout.decode())
PYEOF
