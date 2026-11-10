---
name: design
description: Turn an idea into an approved spec - brainstorm it, grill the user on it, write it down. Use for "let's build X", "I have an idea", "brainstorm", "spec this", /design, and before any change that adds a feature or alters behaviour and has no spec yet.
---

# Design

From an idea to a spec the user has approved. Nothing is implemented here.
The spec is one file, `docs/specs/<slug>.md`, unless the project's
instructions name another place; the plan is later appended to the same file.

## 1. Brainstorm

- Read first: the code, docs and memory the idea touches. Never ask what you
  can look up.
- Say the idea back in two lines: who it is for and what must be true when it
  is done.
- Ask only what changes the design, one question at a time, each with the
  answer you would pick.
- Offer two or three approaches, smallest first. For each: what it reuses,
  what it skips, what it costs. Say which you would take. "Do nothing" and
  "delete something instead" are approaches when they solve it.

## 2. Grill

Run the `grill` skill on the approach the user picked. Its decision list
becomes the spec's Decisions section.

## 3. Spec

Write the file with these parts, each as short as it can be and still be
checked. A part with nothing in it says "none".

1. **Goal.** What must be true when this is done, and for whom.
2. **Out of scope.** Every feature, option and flexibility skipped, by name.
3. **Decisions.** Each with the alternative that was declined and why.
4. **Design.** What changes and where: data, interfaces, screens, copy. Name
   the existing code it reuses. A choice the user must see (a layout, a
   wording) is shown, not described.
5. **Risks.** Data it could destroy or expose, callers that could stop
   working, and what prevents each.
6. **Acceptance.** Statements a test or a person can check, one per line.

Then re-read it once as the implementer would: fix any line that could be
read two ways, and any step that depends on something the spec never says.

## 4. Approval

The user reads the file and approves it or changes it. Commit it only if the
project tracks its specs. Next: the `write-plan` skill.
