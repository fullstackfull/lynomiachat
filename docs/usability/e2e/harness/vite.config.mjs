// Build of the usability harness (docs/usability/07-e2e.md). A tiny Vue app that mounts the real components this
// phase changed, with the dashboard's real stylesheet, real English and Arabic strings and a real router, and with the
// store, account and Commerce options replaced by fixtures. It needs no Rails, no database and no network, so the
// journeys run in a real browser against the real components.
import path from 'path';
import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import tailwindcss from 'tailwindcss';
import autoprefixer from 'autoprefixer';

const root = path.resolve(import.meta.dirname, '../../../..');
const js = file => path.resolve(root, 'app/javascript', file);
const stub = file => path.resolve(import.meta.dirname, 'stubs', file);

export default defineConfig({
  plugins: [vue()],
  root: import.meta.dirname,
  base: './',
  resolve: {
    alias: [
      // The fixtures, before the broader aliases below.
      { find: /^dashboard\/composables\/store$/, replacement: stub('store.js') },
      { find: /^dashboard\/composables\/store\.js$/, replacement: stub('store.js') },
      { find: /^dashboard\/composables\/useAccount$/, replacement: stub('useAccount.js') },
      { find: /^dashboard\/composables\/useAdmin$/, replacement: stub('useAdmin.js') },
      { find: /^dashboard\/composables\/usePolicy$/, replacement: stub('usePolicy.js') },
      { find: /^dashboard\/composables$/, replacement: stub('composables.js') },
      {
        find: /^dashboard\/components-next\/filter\/audienceProvider$/,
        replacement: stub('audienceProvider.js'),
      },
      { find: 'vue', replacement: 'vue/dist/vue.esm-bundler.js' },
      { find: 'components', replacement: js('dashboard/components') },
      { find: 'next', replacement: js('dashboard/components-next') },
      { find: 'dashboard', replacement: js('dashboard') },
      { find: 'helpers', replacement: js('shared/helpers') },
      { find: 'shared', replacement: js('shared') },
      { find: 'assets', replacement: js('dashboard/assets') },
    ],
  },
  // The dashboard's own Tailwind configuration, named explicitly: the harness lives outside the repository root, so
  // nothing else would find it. Run the build from the repository root, where its content globs resolve.
  css: {
    postcss: {
      plugins: [
        tailwindcss({ config: path.resolve(root, 'tailwind.config.js') }),
        autoprefixer(),
      ],
    },
  },
  build: { outDir: 'dist', emptyOutDir: true },
});
