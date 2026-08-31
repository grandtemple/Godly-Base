# Godly-Base

A multi-agent feature pipeline for Claude Code: a `/ship` command chains four
specialist subagents — Planner, Coder, Tester, Reviewer — each handing off
work to the next via files in `.pipeline/`.

## How it works

1. **Planner** (`opus`) reads the codebase and turns your feature request into
   a spec at `.pipeline/spec.md`. It writes no code. Ambiguities are flagged
   as `OPEN QUESTION`s instead of guessed at.
2. **Coder** (`sonnet`) implements exactly what the spec describes and
   summarizes the changes at `.pipeline/changes.md`.
3. **Tester** (`sonnet`) writes and runs tests based on the changes and spec,
   recording the outcome at `.pipeline/test-results.md`. It does not fix
   failing code — a failure pauses the pipeline.
4. **Reviewer** (`opus`, read-only) reads the spec, changes, diff, and test
   results, then writes a verdict — `SHIP`, `NEEDS WORK`, or `BLOCK` — to
   `.pipeline/review.md`.

The pipeline never merges anything. It stops after the Reviewer's verdict and
leaves the branch for you to review.

## Usage

```
/ship add rate limiting to the login endpoint
```

Agent definitions live in `.claude/agents/`; the orchestrator command lives at
`.claude/commands/ship.md`. The `.pipeline/` handoff folder is created at
runtime and is git-ignored — clear it between runs so agents don't read stale
output from a previous feature.
