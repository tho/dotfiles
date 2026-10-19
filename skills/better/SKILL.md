---
name: better
description: 'Deepens a prompt or the work in progress. Use when the user explicitly types /better or $better, never otherwise.'
disable-model-invocation: true
---

I want a deeper version of this task, not a bigger one. Before rewriting it: (1) say what a top professional in this field would do here that I'm not asking for; (2) name the rawest material they would start from instead of what has already been digested for me; (3) name the specific methods and tools they would use; (4) say what, other than you or me, would show the result is right. Then rewrite my prompt to ask for exactly that.

## How to apply it

**Case A: the user gave you a prompt or task they have not started.** Answer (1) to (4), give the rewritten prompt, and stop there; the user decides whether to run it.

**Case B: the command came alone or with feedback ("too shallow") on work you have already done in this conversation.** That work plus the feedback is the task.

1. Answer (1) to (4) in a few lines each, then rewrite the brief: the original request plus the feedback, deepened by your answers.
2. If the new brief changes the goal, widens the scope, or needs a decision, money or access only the user can give, show it and wait for their go-ahead.
3. Redo the work to the new brief: start from the raw material in (2), use the methods and tools in (3), and before reporting, run the check in (4) and say what it showed.
