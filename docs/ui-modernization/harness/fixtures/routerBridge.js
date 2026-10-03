// `dashboard/routes/index.js` builds the real router AND imports the whole route tree and the real store, so any
// component that imports it (BackButton does, by relative path) drags the entire application graph in and deadlocks
// on Chatwoot's own circular imports. The harness resolves that module to this bridge instead, and main.js points
// the bridge at the harness router once it exists. Nothing calls it before then — BackButton only uses it on click.
const bridge = {
  push: () => Promise.resolve(),
  replace: () => Promise.resolve(),
  go: () => {},
  back: () => {},
  resolve: to => ({ href: '#', ...(typeof to === 'object' ? to : {}) }),
  currentRoute: { value: { name: '', params: {}, query: {} } },
};

export const attachRouter = router => {
  bridge.push = (...args) => router.push(...args).catch(() => {});
  bridge.replace = (...args) => router.replace(...args).catch(() => {});
  bridge.go = (...args) => router.go(...args);
  bridge.back = () => router.back();
  bridge.resolve = (...args) => router.resolve(...args);
  bridge.currentRoute = router.currentRoute;
};

export const router = bridge;
export default bridge;
