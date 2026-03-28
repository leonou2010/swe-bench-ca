Check progress of all running SWE-bench Pro experiments and give a status report.

## Instructions

1. Find all running experiments by checking for trajectory files in:
   - `exp_nano_full_baseline/results/*/`
   - `exp_nano_full_ca/results/*/`
   - Any other `exp_*/results/*/` directories

2. For each experiment, report:
   - Instances done / total
   - Avg steps
   - Forfeits count
   - Estimated cost
   - Whether eval has started or completed

3. Check system health:
   - CPU load (`cat /proc/loadavg`)
   - RAM (`free -h`)
   - Docker containers (`docker ps -q | wc -l`)

4. If eval is complete, report:
   - Correct / total = accuracy
   - Conditional accuracy (intentional submits only)
   - Forfeit count and rate

5. Flag any problems:
   - CPU > 80% sustained
   - RAM > 80%
   - Any instance with > 200 API calls (call limit broken)
   - Process not running (crashed)
