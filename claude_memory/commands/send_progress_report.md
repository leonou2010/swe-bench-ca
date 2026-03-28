Send a progress report email for all running SWE-bench Pro experiments.

## Instructions

Run the progress report script:
```bash
bash /home/ka3094/aysm/progress_report.sh
```

This will:
1. Check all running experiments (trajectory count, forfeits, cost, ETA)
2. Check system health (CPU, RAM, containers)
3. Check if evals are complete
4. Print the report to stdout
5. Email it to leonau1769@gmail.com via Gmail SMTP

The email script is at `/home/ka3094/aysm/send_email.py`.
The progress script is at `/home/ka3094/aysm/progress_report.sh`.
