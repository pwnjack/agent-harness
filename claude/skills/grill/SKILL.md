---
name: grill
description: Challenge the user on a design, plan or decision with hard questions until nothing open would change it. Use for "grill me", "challenge this", "poke holes", "what am I missing", /grill, and as the second step of the design skill.
---

# Grill

Question a design until every decision in it is made on purpose. The subject
is whatever the user names: an idea, a spec, a plan, a diff, a habit.

- **Look before asking.** A question the code, the docs or memory can answer
  is answered there, and you report what you found.
- **One question at a time**, the one whose answer changes the most first.
  Each comes with the answer you would give and what that answer costs.
- **Follow the answer.** A decision opens the ones that depend on it; settle
  those before moving to another branch.
- **Push back.** When an answer is weak, say why and ask again. "Later",
  "flexible" and "just in case" are not answers: either it is in or it is
  named as skipped.
- **Disagree out loud.** If you think the user is wrong, say it once with the
  evidence, then go with their call and record it.

What to attack, in this order:

1. Does it need to exist? What happens if nothing is built?
2. What already does this, here or in the platform?
3. What is the smallest version that does the core job, and what is everyone
   assuming it must also do?
4. Who loses data, access or a working feature if it goes wrong?
5. The edges: empty, first use, the thousandth item, two people at once, a
   failure half way, no network, the wrong role.
6. How will anyone know it works, and know when it stops working?

Stop when no open question would change the design. End with the list:

```
Decided:  <decision> (instead of <alternative>, because <reason>)
Skipped:  <what was left out, by name>
Open:     <what only the user can still settle>, or none
```

Inside the `design` skill this list goes into the spec. On its own, it is the
answer.
