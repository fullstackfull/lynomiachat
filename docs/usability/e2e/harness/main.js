import { createApp } from 'vue';
import { createI18n } from 'vue-i18n';
import { createRouter, createMemoryHistory } from 'vue-router';
import FloatingVue from 'floating-vue';
import { directive as onClickaway } from 'vue3-click-away';
import en from 'dashboard/i18n/locale/en/index.js';
import ar from 'dashboard/i18n/locale/ar/index.js';
import App from './App.vue';
import 'dashboard/assets/scss/app.scss';

const params = new URLSearchParams(window.location.search);
const locale = params.get('locale') === 'ar' ? 'ar' : 'en';
document.documentElement.setAttribute('dir', locale === 'ar' ? 'rtl' : 'ltr');
document.documentElement.setAttribute('lang', locale);

// The real route records the cross-module actions resolve, with the meta that gates them.
const router = createRouter({
  history: createMemoryHistory(),
  routes: [
    { path: '/', name: 'harness', component: { template: '<div />' } },
    {
      path: '/automation',
      name: 'automation_list',
      component: { template: '<div />' },
      meta: { featureFlag: 'automations', permissions: ['administrator'] },
    },
    {
      path: '/campaigns/whatsapp',
      name: 'campaigns_whatsapp_index',
      component: { template: '<div />' },
      meta: {
        featureFlag: 'whatsapp_campaigns',
        permissions: ['administrator'],
      },
    },
  ],
});

// As the dashboard does it: created on `en`, then switched. vue-i18n falls back to the creation locale, so a key
// Crowdin has not translated yet renders in English inside the Arabic UI — exactly what the product does.
const i18n = createI18n({ legacy: false, locale: 'en', messages: { en, ar } });
i18n.global.locale.value = locale;

const app = createApp(App);
app.use(i18n);
app.use(router);
app.use(FloatingVue);
app.directive('on-clickaway', onClickaway);
router.isReady().then(() => app.mount('#app'));
