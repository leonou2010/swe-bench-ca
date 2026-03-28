---
name: Use trajectory viewer for analysis
description: User prefers the lazy-loading HTML trajectory viewer for exploring SWE-bench Pro results
type: feedback
---

When doing analysis on SWE-bench Pro experiment results, use the trajectory viewer (exp1/report/viewer.html) served via HTTP. The user finds it works well and wants it used going forward.

**Why:** The viewer shows problem statements, full trajectories (thought/action/observation), and patches with diff coloring — all in one UI with filtering by repo/status/search. Much better than reading raw JSON.

**How to apply:**
- Rebuild viewer (`python exp1/report/build_viewer.py`) whenever results change
- Serve with `python3 -m http.server 8888 --directory exp1/report`
- For new experiments, generate the same viewer structure (lazy-load: small HTML + per-instance JSON in data/)
- Reference the viewer when discussing specific instances rather than dumping raw trace data
