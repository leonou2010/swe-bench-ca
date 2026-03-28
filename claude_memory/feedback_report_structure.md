---
name: Report structure for supervisor
description: Reports need two layers - 5-min overview then 30-min deep dive with code references
type: feedback
---

Reports for the supervisor must be structured as two layers:

**Part I (5-minute read)**: High-level overview. Flow diagrams (ASCII), summary tables, no code. Reader should understand the full picture without scrolling past Part I.

**Part II (30-minute read)**: Deep dive with actual code snippets, file:line references, exception tables, annotated walkthroughs. Same topics as Part I but with implementation detail.

**Why:** User said "a good report need to be both a 5 min read and a 30 minute read." The supervisor is technical but needs to scan quickly first, then drill in.

**How to apply:**
- Always start with a high-level flow diagram showing the end-to-end process
- Summary tables for key concepts (how the loop ends, what we measure, etc.)
- No code in Part I
- Part II repeats the same sections with code references and file paths
- File paths are local (relative to project root), not GitHub URLs
- No results in the process doc — those go in REPORT.md
- Separate concerns: SETUP_AND_PROCESS.md (how things work) vs REPORT.md (what we found)
