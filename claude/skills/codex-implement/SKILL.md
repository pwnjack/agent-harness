---
name: codex-implement
description: Use when the user asks Codex specifically to implement, build, write, or fix something (e.g. "have codex do X", "get codex to implement Y"), or when running /codex-implement. Alias for delegate-implement with the executor pinned to Codex.
---

# Codex Implement

Alias. Invoke `delegate-implement` with **executor `codex`**.

Pick the Codex alias and reasoning effort from the task shape, per the
implementer table in `auto-subagent-routing` Step 2 — the lightest that handles
it well. Choose `astra` or `inherit` (the user's `~/.codex/config.toml` model)
only when the user explicitly asks for them — `astra` eats their usage. The
spawn may still fall back to `inherit` on its own when an alias cannot be
resolved, and says so. Never `ultra`. Aliases resolve to the newest model of
that name at launch; see *Model selection* in
`~/.claude/skills/_shared/handoff.md`.

Everything else — the brief, the report-file handoff, the fresh pane per
delegation, independent verification — is `delegate-implement`'s, and the mechanics are in
`~/.claude/skills/_shared/handoff.md`.

**If Codex is unavailable** (not installed, not logged in, or no Herdr session),
do not fail: fall to the tier the capability probe selects, and tell the user
which executor actually ran.

Per the adversarial pairing rule, code Codex writes is reviewed by Claude
(`sonnet` or `opus` per *Review tier*) — not by Codex.
