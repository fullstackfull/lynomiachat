// Build of the UI modernization harness (docs/ui-modernization/03-harness.md). Mirrors the dashboard's own Vite
// aliases so the real components, the real routes and the real stylesheet all resolve. Run from the repository root,
// where Tailwind's content globs resolve.
import path from 'path';
import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import yaml from '@rollup/plugin-yaml';
import tailwindcss from 'tailwindcss';
import autoprefixer from 'autoprefixer';

const root = path.resolve(import.meta.dirname, '../../..');
const js = file => path.resolve(root, 'app/javascript', file);

// `dashboard/routes/index.js` is the app's router module: it imports the whole route tree and the real Vuex store.
// Any component importing it (BackButton, by relative path) pulls the entire graph into whatever chunk it lands in
// and deadlocks on a circular import. Resolve it to the harness bridge instead.
const breakRouterCycle = () => ({
  name: 'harness-break-router-cycle',
  enforce: 'pre',
  resolveId(source, importer) {
    if (!importer || !/(^|\/)routes(\/index(\.js)?)?$/.test(source)) return null;
    return this.resolve(source, importer, { skipSelf: true }).then(resolved => {
      if (!resolved) return null;
      const normalized = resolved.id.replace(/\\/g, '/');
      return normalized.endsWith('app/javascript/dashboard/routes/index.js')
        ? path.resolve(import.meta.dirname, 'fixtures/routerBridge.js')
        : null;
    });
  },
});

export default defineConfig({
  plugins: [
    breakRouterCycle(),
    vue({ template: { compilerOptions: { isCustomElement: tag => ['ninja-keys'].includes(tag) } } }),
    yaml(),
  ],
  root: import.meta.dirname,
  base: './',
  define: { 'process.env': {} },
  resolve: {
    alias: {
      vue: 'vue/dist/vue.esm-bundler.js',
      components: js('dashboard/components'),
      next: js('dashboard/components-next'),
      v3: js('v3'),
      dashboard: js('dashboard'),
      helpers: js('shared/helpers'),
      shared: js('shared'),
      survey: js('survey'),
      widget: js('widget'),
      assets: js('dashboard/assets'),
    },
  },
  css: {
    postcss: {
      plugins: [
        tailwindcss({ config: path.resolve(root, 'tailwind.config.js') }),
        autoprefixer(),
      ],
    },
  },
  build: { outDir: 'dist', emptyOutDir: true, chunkSizeWarningLimit: 8000, minify: false },
});
