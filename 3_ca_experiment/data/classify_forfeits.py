#!/usr/bin/env python3
"""Classify forfeit-with-code instances by pattern.

Reads trajectories from exp5/results/swe_agent_ultra_cautious/.
Outputs classification to stdout.

Pattern rules:
- submitted_then_forfeit: model called `submit` at any point in the trajectory
- edit_failed: last 5 steps contain "No replacement was performed"  
- empty_actions: last 5 steps contain 2+ empty actions
- exploring: everything else (model was searching/reading code)
"""
import json, glob, sys
from collections import Counter

traj_dir = sys.argv[1] if len(sys.argv) > 1 else 'exp5/results/swe_agent_ultra_cautious'
eval_path = f'{traj_dir}/docker_eval/eval_results.json'

with open(eval_path) as f:
    eval_results = json.load(f)

results = []
for tf in sorted(glob.glob(f'{traj_dir}/*/*.traj')):
    with open(tf) as f:
        t = json.load(f)
    if t.get('info', {}).get('exit_status', '') != 'submitted (exit_forfeit)':
        continue
    
    iid = tf.split('/')[-2]
    traj = t.get('trajectory', [])
    resolved = eval_results.get(iid)
    
    called_submit = any((s.get('action', '') or '').strip() == 'submit' for s in traj)
    last5 = traj[max(0, len(traj)-6):len(traj)-1]
    had_failed_edit = any('No replacement was performed' in (s.get('observation', '') or '') for s in last5)
    had_empty = sum(1 for s in last5 if not (s.get('action', '') or '').strip()) >= 2
    
    if called_submit:
        cat = 'submitted_then_forfeit'
    elif had_failed_edit:
        cat = 'edit_failed'
    elif had_empty:
        cat = 'empty_actions'
    else:
        cat = 'exploring'
    
    results.append({'id': iid, 'category': cat, 'resolved': resolved, 'steps': len(traj)})

for cat in ['submitted_then_forfeit', 'exploring', 'edit_failed', 'empty_actions']:
    items = [r for r in results if r['category'] == cat]
    wp = sum(1 for r in items if r['resolved'] == True)
    wf = sum(1 for r in items if r['resolved'] == False)
    total = wp + wf
    acc = f"{100*wf/total:.0f}%" if total else "n/a"
    print(f"{cat:30s}  count={len(items):>3}  would_pass={wp:>2}  would_fail={wf:>2}  forfeit_acc={acc}")

print(f"\nTotal: {len(results)}")

# Output JSON for audit
import json as j
j.dump(results, open(f'{traj_dir}/forfeit_classifications.json', 'w'), indent=2)
print(f"Saved to {traj_dir}/forfeit_classifications.json")
