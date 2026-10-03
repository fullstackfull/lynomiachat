<script setup>
// The three surfaces this phase changed, each on its own panel, so a journey can act on the real component in a real
// browser at a real viewport in either direction.
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ContactMoreActions from 'dashboard/components-next/Contacts/ContactsHeader/components/ContactMoreActions.vue';
import RecipeDialog from 'dashboard/components-next/recipes/RecipeDialog.vue';
import { AUDIENCE_PRESETS } from 'dashboard/recipes/audiencePresets';
import { AUTOMATION_RECIPES } from 'dashboard/recipes/automationRecipes';
import { FLOW_TEMPLATES } from 'dashboard/recipes/flowTemplates';
import { FIXTURES } from './stubs/fixtures';

const { t, locale } = useI18n();

const panel = ref(new URLSearchParams(window.location.search).get('panel') || 'audience-menu');
const segment = ref(
  new URLSearchParams(window.location.search).get('segment') === 'personal'
    ? FIXTURES.contactViews[1]
    : new URLSearchParams(window.location.search).get('segment') === 'none'
      ? null
      : FIXTURES.contactViews[0]
);

const CATALOGUES = {
  'flow-templates': { recipes: FLOW_TEMPLATES, title: 'RECIPES.FLOW.TITLE', description: 'RECIPES.FLOW.DESCRIPTION' },
  'automation-recipes': { recipes: AUTOMATION_RECIPES, title: 'RECIPES.AUTOMATION.TITLE', description: 'RECIPES.AUTOMATION.DESCRIPTION' },
  'audience-presets': { recipes: AUDIENCE_PRESETS, title: 'RECIPES.AUDIENCE.TITLE', description: 'RECIPES.AUDIENCE.DESCRIPTION' },
};

const dialogRef = ref(null);
const created = ref(null);
const scratched = ref(false);

const openDialog = () => dialogRef.value?.open();
const onCreate = (recipe, values) => {
  created.value = { id: recipe.id, type: recipe.type, values, payload: recipe.build(values) };
};

defineExpose({ created, scratched, locale, panel, openDialog });
window.harness = { created, scratched, locale, panel, openDialog };
</script>

<template>
  <div class="min-h-screen bg-n-background p-4 font-inter">
    <p id="harness-alert" class="min-h-5 text-sm text-n-slate-11" />

    <section v-if="panel === 'audience-menu'" class="flex justify-end">
      <ContactMoreActions :segment="segment" />
    </section>

    <section v-else class="flex flex-col items-start gap-3">
      <button
        id="harness-open"
        type="button"
        class="rounded-lg bg-n-brand px-3 py-1.5 text-sm text-white"
        @click="openDialog"
      >
        {{ t(CATALOGUES[panel].title) }}
      </button>
      <RecipeDialog
        ref="dialogRef"
        :recipes="CATALOGUES[panel].recipes"
        :title="t(CATALOGUES[panel].title)"
        :description="t(CATALOGUES[panel].description)"
        @create="onCreate"
        @scratch="scratched = true"
      />
    </section>
  </div>
</template>
