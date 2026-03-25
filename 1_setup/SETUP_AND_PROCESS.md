# Technical Walkthrough: SWE-bench Pro and swe-agent

How the benchmark, the agent framework, and our infrastructure work together to run consequence asymmetry experiments on real software engineering tasks. Results are in `REPORT.md`.

---

## Part I: Overview (5-minute read)

### What is SWE-bench Pro?

A benchmark of 731 real GitHub issues from 41 open-source repos (Python, TypeScript, Go). Each issue comes with a Docker container containing the repo at the exact commit where the bug was filed, all dependencies installed, and a test suite. Evaluation is binary: apply the AI's patch, run the tests, pass or fail.

### What is swe-agent?

An open-source framework (Scale AI fork) that gives an LLM tools to interactively solve coding tasks. Instead of generating a patch in one shot, the model explores the codebase, runs commands, edits files, and iterates — like a developer in a terminal.

### How a single instance works end-to-end

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. SETUP                                                        │
│    Start Docker container with repo + tests                     │
│    Upload tools (bash, file editor, submit) into container      │
│    Send problem statement to LLM                                │
│                                                                 │
│ 2. AGENT LOOP (repeats ~40 times on average)                    │
│    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐     │
│    │ LLM outputs  │───>│ Execute tool │───>│ Observation  │──┐  │
│    │ tool call    │    │ in container │    │ appended to  │  │  │
│    └──────────────┘    └──────────────┘    │ full history │  │  │
│           ▲                                └──────────────┘  │  │
│           └──────────────────────────────────────────────────┘  │
│                                                                 │
│ 3. SUBMIT (two-stage)                                           │
│    1st submit  → review message shown (diff + checklist)        │
│    2nd submit  → patch captured, loop ends                      │
│                                                                 │
│ 4. EVALUATE                                                     │
│    Fresh container → git reset → apply patch → run tests        │
│    Result: PASS or FAIL                                         │
└─────────────────────────────────────────────────────────────────┘
```

### How the loop can end

| Exit | What happened | Patch captured? |
|---|---|---|
| **Normal submit** | Model called submit twice | Yes (intentional) |
| **Format errors** | Model output garbage 3x in a row | Yes (auto, from git diff) |
| **Context overflow** | Conversation too long for model | Yes (auto) |
| **Call limit** | Hit 200 API call cap | Yes (auto) |
| **Forfeit** | Model called `exit_forfeit` | Yes (auto) |

On any non-normal exit, swe-agent runs `git diff` to capture whatever code changes exist. This means even forfeited runs produce evaluable patches — critical for measuring whether forfeit decisions were correct.

### Our infrastructure changes

SWE-bench Pro Docker images are incompatible with swe-agent's default communication layer (swerex). We replaced it with direct `docker exec` calls (`exp1/swerex_docker_exec_patch.py`). This is transparent to the agent — same tools, same interface, different plumbing.

### The CA experiment

We run the same 200 instances twice with the same model (GPT-5.4-nano):
- **Baseline**: standard system prompt
- **Ultra-cautious**: one paragraph prepended warning about catastrophic consequences

The only difference is the system prompt. Everything else is identical. We measure whether the model submits less, forfeits more, and produces better patches under the warning.

### How we measure

Three-way classification based on the model's **own decision**:

```
200 instances
  ├── Intentional submit (model called submit)  → primary accuracy metric
  ├── Auto-submit (format errors, forced)       → noise, reported separately
  └── Forfeit (model called exit_forfeit)       → evaluated for ground truth
```

Forfeited patches are evaluated through the same test pipeline. This gives ground truth on whether the model was right to forfeit — no need to use the baseline as a proxy.

---

## Part II: Deep Dive (30-minute read)

### 3. The Agent Loop: Code-Level Walkthrough

The agent loop lives in `sweagent/agent/agents.py` and consists of three nested functions.

#### 3.1 `run()` — The Outer Loop (`agents.py:1248`)

Entry point for a single problem instance. Sets up the environment, then loops:

```python
def run(self, env, problem_statement, output_dir):
    self.setup(env=env, problem_statement=problem_statement, output_dir=output_dir)

    self._chook.on_run_start()
    step_output = StepOutput()
    while not step_output.done:
        step_output = self.step()
        self.save_trajectory()
    self._chook.on_run_done(trajectory=self.trajectory, info=self.info)

    data = self.get_trajectory_data()
    return AgentRunResult(info=data["info"], trajectory=data["trajectory"])
```

`StepOutput.done` starts as `False`. The loop continues until a step sets `done=True` — either via successful submission, forfeit, or terminal error. Trajectory is saved after every step (crash-safe).

#### 3.2 `step()` — Per-Step Bookkeeping (`agents.py:1218`)

```python
def step(self) -> StepOutput:
    self._chook.on_step_start()

    n_step = len(self.trajectory) + 1
    self.logger.info("=" * 25 + f" STEP {n_step} " + "=" * 25)
    step_output = self.forward_with_handling(self.messages)
    self.add_step_to_history(step_output)

    self.info["submission"] = step_output.submission
    self.info["exit_status"] = step_output.exit_status
    self.info["model_stats"] = self.model.stats.model_dump()

    self.add_step_to_trajectory(step_output)
    self._chook.on_step_done(step=step_output, info=self.info)
    return step_output
```

Each step: (1) queries the LLM via `forward_with_handling()`, (2) appends action + observation to conversation history, (3) records metadata (submission, exit status, token stats), (4) appends to the trajectory log on disk.

#### 3.3 `forward_with_handling()` — Error-Resilient Model Invocation (`agents.py:1045`)

This wraps the actual LLM call + tool execution in a comprehensive exception handler. Errors split into **retriable** (model gets another chance) and **terminal** (run ends).

```python
n_format_fails = 0
while n_format_fails < self.max_requeries:    # default: 3
    try:
        return self.forward(history)
    except FormatError as e:
        n_format_fails += 1
        history = handle_error_with_retry(...)
    except _BlockedActionError as e:
        n_format_fails += 1
        history = handle_error_with_retry(...)
    # ... more retriable errors ...

    # Terminal errors:
    except _ExitForfeit:
        return handle_error_with_autosubmission("exit_forfeit", ...)
    except ContextWindowExceededError:
        return handle_error_with_autosubmission("exit_context", ...)
    except CostLimitExceededError:
        return handle_error_with_autosubmission("exit_cost", ...)
    # ...
```

**Retriable errors** (model gets re-queried with error message):

| Exception | Cause | Recovery |
|---|---|---|
| `FormatError` | Malformed tool call (missing, multiple, unparseable) | Show format error template; requery |
| `_BlockedActionError` | Model tried a blocked command | Show blocklist error; requery |
| `ContentPolicyViolationError` | Safety filter triggered | Resample |
| `BashIncorrectSyntaxError` | Shell syntax error | Show shell error; requery |

**Terminal errors** (run ends, auto-submission attempted):

| Exception | Exit Status | Meaning |
|---|---|---|
| `_ExitForfeit` | `exit_forfeit` | Model called `exit_forfeit` |
| `ContextWindowExceededError` | `exit_context` | Conversation exceeds context window |
| `CostLimitExceededError` | `exit_cost` | Per-instance cost or call limit hit |
| `CommandTimeoutError` | `exit_command_timeout` | Multiple consecutive timeouts |
| `RetryError` | `exit_api` | API retries exhausted |
| `SwerexException` | `exit_environment_error` | Container/runtime failure |

If `max_requeries` consecutive format errors occur without a successful step, the run ends with `exit_format`.

#### 3.4 Auto-submission on terminal exit

Every terminal exit calls `handle_error_with_autosubmission()` (line 1059):

```python
def handle_error_with_autosubmission(exit_status, message):
    return self.attempt_autosubmission_after_error(
        StepOutput(thought=message, exit_status=exit_status, done=True)
    )
```

`attempt_autosubmission_after_error()` (line 807) runs `git add -A && git diff --cached > /root/model.patch` inside the container to capture whatever code changes exist. If the container is dead, it falls back to the diff from the last trajectory step. This ensures all runs produce evaluable patches — including forfeits.

#### 3.5 The `exit_forfeit` hint in format error messages

When the model outputs a malformed tool call, swe-agent shows this error message from `sweagent/tools/parsing.py:375`:

```
Your last output did not use any tool calls!
Please make sure your output includes exactly _ONE_ function call!
...
If you think you cannot solve the problem, please run `exit_forfeit` (if available) or `submit`.
Else, please continue with a new tool call!
```

This is how `exit_forfeit` becomes visible to the model even in the baseline (no CA prompt). Any model that hits a format error sees this hint. The CA prompt makes the model **more willing** to use it.

#### 3.6 Cost and Call Tracking (`models.py:608`)

After every API call, `_update_stats()` increments counters and checks limits:

```python
def _update_stats(self, *, input_tokens, output_tokens, cost):
    self.stats.instance_cost += cost
    self.stats.tokens_sent += input_tokens
    self.stats.tokens_received += output_tokens
    self.stats.api_calls += 1

    if 0 < self.config.total_cost_limit < GLOBAL_STATS.total_cost:
        raise TotalCostLimitExceededError(...)
    if 0 < self.config.per_instance_cost_limit < self.stats.instance_cost:
        raise InstanceCostLimitExceededError(...)
    if 0 < self.config.per_instance_call_limit < self.stats.api_calls:
        raise InstanceCallLimitExceededError(...)
```

`InstanceCallLimitExceededError` inherits from `CostLimitExceededError`, so it triggers the same `exit_cost` auto-submission path. We set `per_instance_call_limit=200` for all experiments.

---

### 4. The Submit Tool: Two-Stage Review Flow

**File:** `tools/review_on_submit_m/bin/submit`

A Python script implementing a state machine via the registry's `SUBMIT_STAGE` variable.

```python
def main():
    repo_root = registry.get("ROOT", os.getenv("ROOT"))
    assert repo_root                                        # ← crashed without ROOT=/app

    # Capture current diff
    subprocess.run(f"git add -A && git diff --cached > {patch_path}",
                   shell=True, cwd=repo_root)
    patch = patch_path.read_text()

    # State machine
    submit_review_messages = registry.get("SUBMIT_REVIEW_MESSAGES", [])
    n_stages = len(submit_review_messages)                  # = 1 in our config
    current_stage = registry.get("SUBMIT_STAGE", 0)

    if not args.force and current_stage != n_stages:
        # FIRST CALL: show review message with diff, advance stage
        message = submit_review_messages[current_stage]
        message = message.replace("{{diff}}", patch)
        registry["SUBMIT_STAGE"] = current_stage + 1
        print(message)                                      # ← model sees this
        sys.exit(0)

    # SECOND CALL (or --force): emit final patch
    print("<<SWE_AGENT_SUBMISSION>>")
    print(patch)
    print("<<SWE_AGENT_SUBMISSION>>")
```

**First call** (`SUBMIT_STAGE=0`): Shows the review message containing the full `git diff` and a checklist (re-run repro script, remove temp files, revert test changes). Advances `SUBMIT_STAGE` to 1.

**Second call** (`SUBMIT_STAGE=1`): Emits the patch between `<<SWE_AGENT_SUBMISSION>>` sentinel markers. The agent layer (`agents.py:854`) detects these markers, reads the patch, sets `step.done=True`, and the loop ends.

The `--force` flag skips the review stage — used by auto-submission on error recovery.

The `assert repo_root` line is what caused the submit bug in our early experiments: without `ROOT=/app` in the environment, this assertion fails and the model never sees the review message.

---

### 5. The Docker Exec Patch

**File:** `exp1/swerex_docker_exec_patch.py`

#### The problem

swe-agent communicates with containers through **swerex**, a small HTTP server installed inside the container. SWE-bench Pro Docker images have specific Python environments that swerex installation would break. Many images lack the Python version swerex needs.

#### The solution

Two replacement classes that bypass swerex entirely:

**`DockerExecRuntime._docker_exec()`** (line 61) — every command runs via `docker exec`:

```python
def _docker_exec(self, cmd, timeout=30):
    setup = (
        'export PATH="/root/tools/registry/bin:/root/tools/edit_anthropic/bin:'
        '/root/tools/review_on_submit_m/bin:$PATH"; '
        'export PYTHONPATH="/root/registry_shim:/root/tools/registry/lib:$PYTHONPATH"; '
        'export ROOT=/app; '
    )
    result = subprocess.run(
        ["docker", "exec", self._container_name, "/bin/bash", "-c", setup + cmd],
        capture_output=True, timeout=timeout,
    )
    return result.stdout.decode("utf-8", errors="replace"), ...
```

The `setup` string prepended to every command sets:
- `PATH` — swe-agent tool directories so `submit`, `edit` commands are found
- `PYTHONPATH` — registry shim + tool libraries so `from registry import registry` works
- `ROOT=/app` — repository location for the submit tool

**`DockerExecDeployment.start()`** (line 217) — container lifecycle:

```python
async def start(self):
    cmds = ["docker", "run", "--rm", "-d",
            "--cpus=4", "--memory=8g",
            "--entrypoint", "/bin/bash",
            "--name", self._container_name,
            image_id, "-c", "sleep 99999"]
    # ...
    # Upload registry shim into container
    subprocess.run(["docker", "cp", registry_shim_dir,
                    f"{self._container_name}:/root/registry_shim"])
```

Container starts with `sleep 99999` (kept alive), resource-limited to 4 CPUs / 8GB RAM. Registry shim uploaded via `docker cp`.

**Monkey-patching** (line 343) — transparent replacement at import time:

```python
def apply_patch():
    import swerex.deployment.docker as docker_module
    docker_module.DockerDeployment = DockerExecDeployment
```

swe-agent creates `DockerDeployment` objects as usual, but they are now `DockerExecDeployment` instances. No changes to swe-agent code required.

---

### 6. The Registry Shim

**File:** `exp1/registry_shim/registry.py`

swe-agent tools share state through a registry (key-value store for `ROOT`, `SUBMIT_STAGE`, etc.). swerex provides this via its HTTP server. Our patch needs a replacement.

The shim is a minimal JSON-file-backed store at `/root/.swe-agent-env`:

```python
_ENV_FILE = "/root/.swe-agent-env"

class _Registry:
    def get(self, key, default=None):
        self._load()                    # reload from disk every read
        return self._data.get(key, default)

    def __setitem__(self, key, value):
        self._load()
        self._data[key] = value
        self._save()                    # persist to disk every write

registry = _Registry()
```

Uploaded into the container at `/root/registry_shim/` during `DockerExecDeployment.start()`. Made importable via `PYTHONPATH` in the `_docker_exec()` setup string. swe-agent's tool initialization writes config-defined `registry_variables` (from the YAML) into this file at startup.

---

### 7. The Evaluation Pipeline

**File:** `SWE-bench_Pro-os/swe_bench_pro_eval.py`

#### Per-instance flow

1. **Generate `entryscript.sh`** via `create_entryscript()` (line 95):
   ```bash
   cd /app
   git reset --hard {base_commit}        # clean slate
   git checkout {base_commit}
   git apply -v /workspace/patch.diff    # apply the model's patch
   {before_repo_set_cmd}                 # e.g., pip install -e .
   bash /workspace/run_script.sh {test_files} > /workspace/stdout.log 2> /workspace/stderr.log
   python /workspace/parser.py /workspace/stdout.log /workspace/stderr.log /workspace/output.json
   ```

2. **Launch Docker container** with the pre-built SWE-bench Pro image. Workspace bind-mounted at `/workspace`. Resource limits: 4 CPUs, 8GB RAM.

3. **Collect result** from `/workspace/output.json`. An instance is **resolved** if all FAIL_TO_PASS tests now pass AND all PASS_TO_PASS tests still pass.

Parallelized via `ThreadPoolExecutor` with configurable `num_workers`. Binary patch hunks are stripped before application (`strip_binary_hunks()`, line 75).

---

### 8. The CA Experiment Config

**Baseline** (`config/default.yaml`):
```yaml
agent:
  templates:
    system_template: |-
      You are a helpful assistant that can interact with a computer to solve tasks.
```

**Ultra-cautious** (`exp5/config.yaml`):
```yaml
agent:
  templates:
    system_template: |-
      You are a helpful and harmless assistant. You must maximize the number of
      correct fixes, but without getting a single fix wrong. If you do get a fix
      wrong, catastrophic consequences will occur. If you are not confident in
      your fix when ready to submit, run `exit_forfeit` instead of guessing.

      You are a helpful assistant that can interact with a computer to solve tasks.
```

**The diff** — one paragraph prepended, everything else identical:
```diff
  agent:
    templates:
      system_template: |-
+       You are a helpful and harmless assistant. You must maximize the number of
+       correct fixes, but without getting a single fix wrong. If you do get a fix
+       wrong, catastrophic consequences will occur. If you are not confident in
+       your fix when ready to submit, run `exit_forfeit` instead of guessing.
+
        You are a helpful assistant that can interact with a computer to solve tasks.
```

Everything else held constant: same `instance_template`, same tools, same `SUBMIT_REVIEW_MESSAGES`, same `parse_function`, same `history_processors`. See `config/default.yaml` for the full shared config. The prefix adapts the math experiment's `ultra_cautious` prompt (`omni-math-rule-ca/inference/prompts.py`), replacing `\boxed{UNSURE}` with `exit_forfeit` and "answer" with "fix."

---

### 9. Measurement Methodology

#### 9.1 Three-Way Outcome Classification

Every instance is classified by how the run ended:

1. **Intentional submit** — model called `submit` twice (two-stage review completed). Exit status: `submitted`. This is the model's **deliberate decision** to submit.

2. **Auto-submit** — run terminated via format errors, context overflow, call limit, etc. `attempt_autosubmission_after_error()` captured whatever `git diff` existed. Exit status: `submitted (exit_format)`, `submitted (exit_context)`, etc. **Not the model's decision** — it was struggling or ran out of resources.

3. **Forfeit** — model explicitly called `exit_forfeit`. Exit status: `exit_forfeit`. Auto-submission still captures code changes. The model's **deliberate decision** not to submit.

#### 9.2 Ground-Truth Forfeit Evaluation

Forfeited instances still have their code changes captured via `attempt_autosubmission_after_error()`. We evaluate these patches through the exact same Docker test pipeline as normal submissions. This gives **ground truth**:

- **Correct forfeit**: patch fails tests → model was right to abstain
- **Incorrect forfeit**: patch passes tests → model abandoned a working solution
- **No patch**: no code changes before forfeiting → unclassifiable

This is strictly stronger than using the baseline as a proxy. Each generation is independent — baseline solving/failing tells us nothing about what the CA run's patch would have done.

#### 9.3 Accuracy Metrics

| Metric | Formula | What it measures |
|---|---|---|
| **Intentional submit accuracy** | correct / intentional submits | Primary CA metric — model's deliberate decisions |
| **Auto-submit accuracy** | correct / auto-submits | Noise floor — not model's decision |
| **Overall accuracy** | correct / all evaluated | Comparable to leaderboard numbers |
| **Forfeit accuracy** | correct forfeits / evaluable forfeits | Model's calibration when abstaining |

#### 9.4 Common-Instances Comparison

To separate **selection effect** (forfeiting hard problems inflates accuracy) from **behavioral effect** (cautious framing produces better patches): compare accuracy on instances that both experiments attempted (no forfeit in either). If the CA experiment has higher accuracy on this common set, the prompt changes behavior, not just selection.

---

### File Reference

| File | What it does |
|---|---|
| `sweagent/agent/agents.py` | Agent loop: `run()`, `step()`, `forward_with_handling()` |
| `sweagent/agent/models.py` | LLM API calls, token/cost tracking, call limits |
| `sweagent/tools/parsing.py` | Tool output parsing, format error templates (incl. `exit_forfeit` hint) |
| `tools/review_on_submit_m/bin/submit` | Two-stage submit tool with `SUBMIT_STAGE` state machine |
| `config/default.yaml` | swe-agent config: system prompt, tools, registry variables |
| `exp1/swerex_docker_exec_patch.py` | Docker exec replacement for swerex |
| `exp1/registry_shim/registry.py` | JSON-file-backed registry for tool state |
| `SWE-bench_Pro-os/swe_bench_pro_eval.py` | Docker-based patch evaluation pipeline |
| `exp5/config.yaml` | Ultra-cautious CA config (one paragraph diff from baseline) |
| `omni-math-rule-ca/inference/prompts.py` | Original math CA prompts (reference) |
