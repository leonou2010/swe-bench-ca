Start or check the disk space watcher that auto-cleans Docker images.

## What it does
Checks disk every 60 seconds. When free space < 20GB:
1. Prunes Docker build cache
2. Removes all SWE-bench Pro Docker images NOT used by running containers

Images get re-pulled when needed. This is a rolling cleanup — pull, use, delete.

## Commands
```bash
# Start watcher
nohup bash /home/ka3094/aysm/disk_watcher.sh > /home/ka3094/aysm/disk_watcher.log 2>&1 &

# Check if running
pgrep -f disk_watcher

# Check log
tail -20 /home/ka3094/aysm/disk_watcher.log

# Stop
pkill -f disk_watcher

# Check disk
df -h /
```
