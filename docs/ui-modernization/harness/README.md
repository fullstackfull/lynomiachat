# The visual harness

The Rails app cannot run in this container (no Docker daemon, a Ruby version mismatch, Postgres down),
so browser verification happens here instead: a Vite app that mounts the **real** page components
against a fixture Vuex store, a fixture axios and a memory router built from the product's own route
names. The components are not stubs — `flows/Index.vue` here is the file that ships.

```
harness/
  main.js            mirrors app/javascript/entrypoints/dashboard.js: same i18n, same plugins, same directives
  App.vue            renders one surface, chosen by ?surface=, inside a frame that matches where it really sits
  surfaces.js        the surfaces the gallery can render — each one a lazy import of a real page
  vite.config.mjs    the dashboard's aliases, the real tailwind.config.js, and the router-cycle breaker
  route-names.mjs    regenerates fixtures/routeNames.js from the product's own *.routes.js files
  shoot.sh           build, then capture
  shoot.mjs          the capture: screenshots + the control inventory
  parity.mjs         the diff that fails on a lost feature
  fixtures/          the account every surface renders against
```

## Capturing

```
bash docs/ui-modernization/harness/shoot.sh docs/ui-modernization/baseline
```

Per surface, per locale (`en`, `ar`), at 390 / 768 / 1024 / 1280 px, it records:

- **the control inventory** — every `button`, `a[href]`, `input`, `select`, `textarea`, `summary` and
  ARIA widget, with the accessible name a screen reader would announce, its `data-test-id`, its icon,
  whether it is disabled, whether it is visible, and whether it has **no** name at all;
- **the page's direction**, so an RTL capture that silently renders LTR is caught;
- **horizontal overflow** in pixels;
- **page errors _and_ console errors** — Vue swallows a failing render into `console.error`, so a
  surface can lose an entire section and still raise no page error;

and screenshots at 390 and 1280.

## Checking parity

```
node docs/ui-modernization/harness/parity.mjs <before-dir> <after-dir>
```

Exits non-zero if, in any of the 144 captures, a control is **lost**, newly **unnamed**, newly
overflowing, newly erroring, or rendering in the wrong direction. A control that genuinely moved is
declared in `parity-exceptions.json` with where it went and why — moving a feature is allowed, losing
one is not, and the difference has to be written down.

## Two things worth knowing before changing the harness

**The router is a bridge, not the real one.** `dashboard/routes/index.js` imports the whole route tree
*and* the real Vuex store, so any component importing it (`BackButton` does, by relative path) drags
the entire app graph into its chunk and deadlocks on a pre-existing circular import. `vite.config.mjs`
resolves that one module to `fixtures/routerBridge.js`; `main.js` builds a memory router from
`fixtures/routeNames.js` and hands it over with `attachRouter()`. No application file is touched.
Regenerate the names with `node docs/ui-modernization/harness/route-names.mjs` — a missing name
silently empties a navigation section rather than erroring.

**Surfaces are kept alive, and resolved before mounting.** Several real pages fetch in `onActivated`,
which never fires outside `<KeepAlive>`. `App.vue` wraps the surface and cycles it once before
capture. The module is awaited rather than wrapped in `defineAsyncComponent`, because the async
wrapper is what keep-alive would cache and Vue reads `activated` hooks off the cached instance at
mount time — before the real component exists.
