# Experiment Index

| ID | Name | Model | N | Description | Status |
|---|---|---|---|---|---|
| exp1_test | swe-single-prompt-test | mixed | 10 | Single-prompt CA test (10 questions x 3 prompts x 3 models) | done |
| exp1 | swe-opus-baseline | claude-opus-4-6 | 200 | SWE-agent baseline with Opus 4.6, 200 instances, 3 workers | done (63.6%) |
| exp2 | swe-haiku-baseline | claude-haiku-4-5 | 23 | SWE-agent baseline with Haiku 4.5 (killed — no turn cap, $247 wasted) | partial |
| exp3 | swe-gpt54nano-baseline | gpt-5.4-nano | 200 | SWE-agent baseline with GPT-5.4-nano, 200 call limit | done (29.8%) |
| exp4 | swe-gpt54nano-cautious | gpt-5.4-nano | 200 | CA: cautious framing ("don't submit incorrect patch") | pending |
| exp5 | swe-gpt54nano-ultra-cautious | gpt-5.4-nano | 200 | CA: catastrophic consequences, 15 forfeits (7.5%) | done (34.1%) |
| exp6 | swe-gpt54nano-reward-1-10 | gpt-5.4-nano | 200 | CA: 1 server saved vs 10 crashed | pending |
| exp7 | swe-gpt54nano-reward-1-humanity | gpt-5.4-nano | 200 | CA: 1 server saved vs infrastructure collapse | pending |
| exp8 | swe-gpt54nano-natural-grading | gpt-5.4-nano | 200 | CA: sprint review, fail on regression | pending |
| exp9_swe | swe-gpt54nano-natural-grading-2 | gpt-5.4-nano | 200 | CA: sprint review with explicit skip option | pending |
