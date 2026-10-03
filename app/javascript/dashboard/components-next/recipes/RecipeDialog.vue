<script setup>
// Start from a recipe (docs/usability/10-recipe-architecture.md). Two steps in one dialog: choose a recipe, then give
// it the account-specific values it needs. "Create" hands the built payload to the page that owns that kind of
// object, which creates it with the ordinary API — so permissions, validation and the audit trail are the usual ones,
// and what comes out is an ordinary editable object.
//
// A recipe whose requirements the account does not meet is shown with what is missing and no Create button: better
// than letting someone build a configuration that cannot work.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import RecipeInputs from './RecipeInputs.vue';
import { INPUT_TYPES, RECIPE_STATUS } from 'dashboard/recipes';
import { useRecipeContext } from 'dashboard/recipes/useRecipeContext';

const props = defineProps({
  recipes: { type: Array, required: true },
  title: { type: String, required: true },
  description: { type: String, default: '' },
  isCreating: { type: Boolean, default: false },
});

const emit = defineEmits(['create', 'scratch']);

const { t } = useI18n();
const { context, loadCommerceOptions, describeAll, presetValues } =
  useRecipeContext();

const dialogRef = ref(null);
const selected = ref(null);
const values = ref({});
const errors = ref({});

const described = computed(() => describeAll(props.recipes));

const open = async () => {
  selected.value = null;
  values.value = {};
  errors.value = {};
  dialogRef.value?.open();
  // The Commerce options decide which recipes are offered and what their pickers hold; one cached call, shared with
  // the contact filter.
  await loadCommerceOptions();
};

const close = () => dialogRef.value?.close();

const choose = recipe => {
  selected.value = recipe;
  values.value = presetValues(recipe);
  errors.value = {};
};

const back = () => {
  selected.value = null;
  errors.value = {};
};

const isBlank = value =>
  value === undefined ||
  value === null ||
  value === '' ||
  (Array.isArray(value) && !value.length);

const validate = () => {
  const found = {};
  selected.value.inputs.forEach(input => {
    const value = values.value[input.key];
    if (input.required && isBlank(value)) {
      found[input.key] = t('RECIPES.ERRORS.REQUIRED');
      return;
    }
    if (input.type === INPUT_TYPES.NUMBER && !isBlank(value)) {
      const number = Number(value);
      const tooSmall = input.min !== undefined && number < input.min;
      const tooLarge = input.max !== undefined && number > input.max;
      if (!Number.isFinite(number) || tooSmall || tooLarge) {
        found[input.key] = t('RECIPES.ERRORS.OUT_OF_RANGE', {
          min: input.min ?? 0,
          max: input.max ?? '∞',
        });
      }
    }
    if (input.type === INPUT_TYPES.URL && !isBlank(value)) {
      try {
        const url = new URL(String(value));
        if (!['http:', 'https:'].includes(url.protocol)) throw new Error();
      } catch {
        found[input.key] = t('RECIPES.ERRORS.INVALID_URL');
      }
    }
  });
  errors.value = found;
  return !Object.keys(found).length;
};

const confirm = () => {
  if (!selected.value || !validate()) return;
  emit('create', selected.value, { ...values.value });
};

// A failed create leaves the dialog, the recipe and the values exactly as they are — the owning page reports the
// error and does not close — so the user fixes one field and tries again instead of starting over.
defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="selected ? t(selected.name) : title"
    :description="selected ? t(selected.description) : description"
    width="2xl"
    overflow-y-auto
    :show-confirm-button="Boolean(selected)"
    :confirm-button-label="t('RECIPES.CREATE')"
    :is-loading="isCreating"
    data-test-id="recipe-dialog"
  >
    <template v-if="!selected">
      <ul class="flex flex-col gap-2 m-0 list-none">
        <li
          v-for="recipe in described"
          :key="recipe.id"
          class="flex items-start justify-between gap-4 p-3 rounded-lg outline outline-1 outline-n-weak"
          :data-test-id="`recipe-${recipe.id}`"
        >
          <span class="flex flex-col min-w-0 gap-1">
            <span class="text-body-main text-n-slate-12">
              {{ t(recipe.name) }}
            </span>
            <span class="text-label-small text-n-slate-11" dir="auto">
              {{ t(recipe.description) }}
            </span>
            <span
              v-if="recipe.status !== RECIPE_STATUS.AVAILABLE"
              class="text-label-small text-n-amber-11"
              :data-test-id="`recipe-${recipe.id}-requirements`"
            >
              {{ t('RECIPES.REQUIRES', { what: recipe.reasons.join(', ') }) }}
            </span>
          </span>
          <Button
            v-if="recipe.status === RECIPE_STATUS.AVAILABLE"
            :label="t('RECIPES.USE')"
            size="sm"
            color="slate"
            variant="faded"
            class="flex-shrink-0"
            :data-test-id="`recipe-${recipe.id}-use`"
            @click="choose(recipe)"
          />
        </li>
      </ul>
      <Button
        :label="t('RECIPES.FROM_SCRATCH')"
        size="sm"
        color="slate"
        variant="link"
        class="self-start"
        data-test-id="recipe-from-scratch"
        @click="emit('scratch')"
      />
    </template>

    <template v-else>
      <RecipeInputs
        v-if="selected.inputs.length"
        v-model="values"
        :inputs="selected.inputs"
        :context="context"
        :errors="errors"
      />
      <p v-else class="mb-0 text-sm text-n-slate-11">
        {{ t('RECIPES.NO_INPUTS') }}
      </p>
      <Button
        :label="t('RECIPES.BACK')"
        size="sm"
        color="slate"
        variant="link"
        class="self-start"
        data-test-id="recipe-back"
        @click="back"
      />
    </template>

    <template #footer>
      <div class="flex items-center justify-between w-full gap-3">
        <Button
          variant="faded"
          color="slate"
          :label="t('DIALOG.BUTTONS.CANCEL')"
          class="w-full"
          type="button"
          @click="close"
        />
        <Button
          v-if="selected"
          :label="t('RECIPES.CREATE')"
          class="w-full"
          :is-loading="isCreating"
          :disabled="isCreating"
          data-test-id="recipe-create"
          @click="confirm"
        />
      </div>
    </template>
  </Dialog>
</template>
