---
title: Automation and flow analytics
description: What your delayed rules did when their moment came, and how your flow runs ended.
position: 50
tags: [analytics, automation, flows]
seo_description: Automation and flow analytics in Lynomia Chat — episodes armed, acted, declined and stranded; runs started, completed and handed to a person.
---
Two screens, one subject: what the machinery did when nobody was watching.

## Automation execution

An **episode** is one delayed rule starting its clock on one conversation. The screen counts episodes, not
rules.

| Tile | What it counts |
|---|---|
| **Episodes armed** | times a delayed rule started its clock in this period |
| **Acted** | episodes whose actions ran |
| **Declined** | episodes the rule re-checked at firing time and chose not to act on |
| **Action rate** | acted as a share of the episodes that reached an outcome |
| **Waiting to fire** | episodes whose clock is still running |
| **Stranded** | episodes whose worker stopped while the actions were running |

**Declined is not a failure.** A delayed rule re-checks its conditions when the clock runs out: "if nobody
has replied in two hours, escalate" should decline when somebody replied. A rule that never declines is
usually a rule whose condition does not depend on anything that can change.

**Stranded above zero is worth investigating.** It means a worker stopped mid-action. Nothing retries these
on purpose, because repeating a send is worse than dropping it — a customer who gets the same message twice
has a worse experience than one who gets it once. If this number is not zero, look at what those episodes
were doing.

**Immediate rules are not here at all.** A rule with no delay runs inline and records nothing to count. The
screen's own note says so. If you have one immediate rule and one delayed rule, this screen is about half
your automation.

## Flow sessions

A **run** is one customer going through one flow once.

| Tile | What it counts |
|---|---|
| **Runs started** | flow runs that began in this period |
| **Reached the end** | runs that ended at an End node |
| **Stopped on an error** | runs that hit an error or a safety limit and were handed to a person |
| **Ended from outside** | runs ended by something else, such as the conversation being resolved |
| **Handed to a person** | runs that reached a handoff node and gave the conversation to your team |
| **Completion rate** | reached the end as a share of the runs that ended in this period |
| **Average run length** | start to end, including every stretch spent waiting for the customer |
| **Average steps** | nodes a run passed through before it ended |
| **Running now** | runs a customer could still answer |

**Handed to a person is a success, not a leak.** A flow that answers the easy half and hands over the rest
is doing its job. The number to worry about is **stopped on an error**: that is a customer who hit a wall.

**Average run length includes waiting.** A flow that asks a question and waits overnight for an answer has
a run length of hours, and that says nothing bad about the flow. Compare runs with each other, not against
a clock.

**Completion rate is measured over runs that ENDED in the period**, not runs that started in it. A run
started yesterday and finished today counts today.

## Limits

- **Finished episodes are kept for 30 days.** Ask for a longer range and the screen says that part of it is
  incomplete, rather than showing a decline that is really a deletion.
- **These screens count machinery, not outcomes.** A flow with a 95% completion rate can still be answering
  the wrong question.

## Related

- [Automation rules](automation-rules)
- [Flow builder](flow-builder)
- [Automation or flow builder](automation-or-flow-builder)
- [Analytics and Reports — which is which](analytics-and-reports)
