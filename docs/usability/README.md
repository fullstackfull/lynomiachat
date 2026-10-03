# Lynomia usability and productivity phase

Making the product that exists faster and safer to use — **not** a visual redesign. The visual pass is a separate
later phase, and what it should take on is in [08](08-deferred-ui-visual-improvements.md).

## What this phase is

```text
DISCOVER the platform → STUDY the workflows → SCORE the friction → DERIVE the recipes → PRIORITIZE → IMPLEMENT
```

| | |
|---|---|
| Improvements implemented | **12** (9 P0, 3 P1) |
| Recipes | **6 flow templates · 7 automation recipes · 7 audience presets** |
| Ruby files changed | **0** |
| Migrations | **0** |
| New tables, endpoints, routes, sidebar items, engines, runtimes or bot models | **0** |
| Tests added | 10 suites; the whole frontend suite stays green at **476 files / 4893 tests** |
| Browser journeys | 16 journeys, 38 checks, 24 screenshots — English and Arabic, desktop and 390px |

## The documents

| | |
|---|---|
| [00](00-role-and-workflow-map.md) | the roles the repository actually defines, and how each moves through the product |
| [01](01-page-friction-audit.md) | page by page: what is already solved, and what is not |
| [02](02-friction-and-opportunity-map.md) | the scored friction list, separating what was observed in code from expected-usage hypotheses |
| [03](03-prioritized-improvements.md) | P0 / P1 / P2, and what was rejected because it already exists |
| [04](04-implemented-productivity-features.md) | every implemented improvement, with before and after step counts |
| [05](05-security-and-permissions.md) | permissions, tenancy, forged input, audit |
| [06](06-performance.md) | what each surface actually fetches |
| [07](07-e2e.md) | the browser journeys, and the honest boundary of the harness |
| [08](08-deferred-ui-visual-improvements.md) | **what the next phase should take on** |
| [09](09-starter-kits-discovery.md) | whether a template mechanism already existed (it did not, and none was built) |
| [09a](09a-recipe-opportunity-study.md) | the study that chose the catalogue, written before any recipe |
| [10](10-recipe-architecture.md) | the manifest contract, instantiation, availability, provenance, safe defaults |
| [11](11-flow-templates.md) · [12](12-automation-recipes.md) · [13](13-audience-presets.md) | the three catalogues |
| [14](14-recipe-e2e.md) | the recipe scenarios and what each suite covers |

## The finding behind all of it

Chatwoot's conversation loop, command palette, keyboard shortcuts, bulk actions and preference storage are already
strong, and this phase deliberately added nothing to them. **Lynomia's own additions — Flow Builder, Audiences,
Commerce — are where the product still made people start from nothing and navigate by memory.** That is where the
budget went.

## Running what this phase added

```bash
pnpm test                                    # the whole frontend suite
docs/usability/e2e/run.sh                    # the browser journeys and screenshots
```
