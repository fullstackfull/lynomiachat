// Mirrors the real dashboard bootstrap (app/javascript/entrypoints/dashboard.js) as closely as the harness can:
// the same i18n, the same UI kit, the same plugins and directives, the product's own routes, and a Vuex store whose
// getters are fixtures. The components under test are the real ones, so what renders here is what ships.
import { createApp } from 'vue';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import { createPinia } from 'pinia';
import { createRouter, createMemoryHistory } from 'vue-router';
import FloatingVue from 'floating-vue';
import { vResizeObserver } from '@vueuse/components';
import { directive as onClickaway } from 'vue3-click-away';

import i18nMessages from 'dashboard/i18n';
import constants from 'dashboard/constants/globals';

import App from './App.vue';
import { GETTERS } from './fixtures/vuexGetters';
import { ROUTE_NAMES } from './fixtures/routeNames';
import { attachRouter } from './fixtures/routerBridge';
import { installFixtureAxios } from './fixtures/api';

import 'floating-vue/dist/style.css';
import 'dashboard/assets/scss/app.scss';

const params = new URLSearchParams(window.location.search);
const locale = params.get('locale') === 'ar' ? 'ar' : 'en';

window.chatwootConfig = { hostURL: 'https://lynomia.test', apiHost: '' };
window.globalConfig = { installationName: 'Lynomia' };
window.WootConstants = constants;
installFixtureAxios();

document.documentElement.setAttribute('dir', locale === 'ar' ? 'rtl' : 'ltr');
document.documentElement.setAttribute('lang', locale);

// Real Vuex, fixture getters. Dispatch is a no-op promise so a page's mount-time fetches resolve quietly.
const store = createStore({ getters: GETTERS, state: () => ({}) });
// Resolves truthy because several pages gate their work on the result (`if (!didFetch) throw`), and `undefined`
// reads as a failed fetch — which would leave those pages showing an error state instead of their real content.
store.dispatch = () => Promise.resolve(true);

// Every real route name, so each `accountScopedRoute(...)` and `router.resolve({ name })` a component makes
// resolves. The components are real; only the destinations are inert.
const Blank = { template: '<div />' };
const router = createRouter({
  history: createMemoryHistory(),
  routes: [
    { path: '/app/accounts/:accountId', name: 'harness_root', component: Blank },
    ...ROUTE_NAMES.map(name => ({
      path: `/app/accounts/:accountId/_r/${name}`,
      name,
      component: Blank,
      meta: { permissions: ['administrator', 'agent', 'custom_role'] },
    })),
  ],
});

attachRouter(router);

// As the dashboard does it: created on `en`, then switched, so a string Crowdin has not translated falls back to
// English exactly as it does in the product.
const i18n = createI18n({ legacy: false, locale: 'en', messages: i18nMessages });
i18n.global.locale.value = locale;

const app = createApp(App);
app.use(i18n);
app.use(store);
app.use(createPinia());
app.use(router);
app.use(FloatingVue, {
  instantMove: true,
  arrowOverflow: false,
  disposeTimeout: 5000000,
  container: '#app',
  themes: { tooltip: { strategy: 'fixed' } },
});
// The legacy globals the audited surfaces actually reference. Registering the whole UI kit pulls Chatwoot's full
// component graph and deadlocks on its circular imports, and none of these affect what is being measured.
const Passthrough = { template: '<div><slot /></div>' };
const Hidden = { template: '<div style="display:none"><slot /></div>' };
app.component('woot-loading-state', { props: ['message'], template: '<div class="p-6 text-sm text-n-slate-11">{{ message }}</div>' });
app.component('woot-delete-modal', Hidden);
app.component('woot-confirm-modal', Hidden);
app.component('woot-modal', Hidden);
app.component('woot-modal-header', Passthrough);
app.component('woot-button', { template: '<button><slot /></button>' });
app.component('fluent-icon', { props: ['icon'], template: '<span />' });
app.directive('resize', vResizeObserver);
app.directive('on-clickaway', onClickaway);

const surface = params.get('surface') || 'flows-list';
const routeName = params.get('route');
const target = routeName
  ? { name: routeName, params: { accountId: '1' } }
  : { name: 'harness_root', params: { accountId: '1' } };

router
  .push(target)
  .catch(() => {})
  .then(() => router.isReady())
  .then(() => app.mount('#app'))
  .catch(error => {
    document.body.innerHTML = `<pre style="padding:16px;font:12px monospace">${surface}: ${error?.stack || error}</pre>`;
  });
