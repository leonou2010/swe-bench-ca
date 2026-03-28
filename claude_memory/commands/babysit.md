Check the status of a running SWE-bench Pro experiment and report any issues.

## Instructions

1. Find which experiment is running:
   - Check `ps aux | grep sweagent` for active processes
   - Check `docker ps` for running containers
   - Check recent log files in `exp*/run_all.log`

2. Report progress:
   - Count completed trajectories: `find expN/results/DIR -name "*.traj" | wc -l`
   - Show last few log lines
   - Check RAM/CPU: `free -h` and `cat /proc/loadavg`

3. Quick health check on recent trajectories:
   - Average step count (should be <100 with ROOT fix)
   - How many produced patches vs failed
   - Any instances exceeding 200 calls (call limit not working?)
   - Exit statuses distribution

4. Red flags to report:
   - Avg steps > 200 → call limit broken, KILL IMMEDIATELY
   - RAM > 80% → containers leaking
   - 0 new trajectories in last 10 min → stuck
   - Docker containers piling up (>5) → something wrong
   - Process not running → crashed, check log

5. Estimate ETA based on:
   - Instances done / total
   - Average time per instance from completed ones

6. If experiment is done (all 200 trajectories):
   - Show summary: patches produced, avg steps, exit status distribution
   - Remind to run docker eval (step 7 in run_all.sh)
   - Remind to build viewer
