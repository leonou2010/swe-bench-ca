---
name: Disk management for SWE-bench experiments
description: Docker images fill disk fast. Must run rolling cleanup during experiments.
type: reference
---

SWE-bench Pro images are 2-5GB each. 731 instances need ~225 unique images = ~660GB. The VM has 788GB total.

**Solution: rolling cleanup.** Run `disk_watcher.sh` during experiments. It deletes unused images every 60s when disk < 20GB free. Images get re-pulled when needed.

**Scripts:**
- `/home/ka3094/aysm/disk_watcher.sh` — auto-cleanup daemon
- Start: `nohup bash disk_watcher.sh > disk_watcher.log 2>&1 &`

**Key lesson:** Both 731-instance runs crashed twice from disk full before the watcher was set up. Always start the watcher BEFORE launching experiments.

**Other space hogs:**
- `exp2/` — 27GB (broken Haiku run, user wants to keep it)
- `exp1/` — 7GB (Opus baseline)
- Docker build cache — prune regularly
