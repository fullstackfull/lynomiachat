<script>
import BackButton from '../../../components/widgets/BackButton.vue';

export default {
  components: {
    BackButton,
  },
  props: {
    headerTitle: {
      default: '',
      type: String,
    },
    showBackButton: { type: Boolean, default: false },
    backUrl: {
      type: [String, Object],
      default: '',
    },
    backButtonLabel: {
      type: String,
      default: '',
    },
  },
};
</script>

<template>
  <div
    class="flex justify-between items-center h-20 min-h-14 px-6 py-2 bg-n-surface-1"
  >
    <h1 class="flex items-center mb-0 text-n-slate-12">
      <BackButton
        v-if="showBackButton"
        :button-label="backButtonLabel"
        :back-url="backUrl"
        class="ltr:mr-4 rtl:ml-4"
      />

      <slot />
      <span class="text-heading-1 text-n-slate-12">
        {{ headerTitle }}
      </span>
    </h1>
  </div>
</template>
