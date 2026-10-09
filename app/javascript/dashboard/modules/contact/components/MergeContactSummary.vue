<script>
export default {
  props: {
    primaryContactName: {
      type: String,
      default: '',
    },
    parentContactName: {
      type: String,
      default: '',
    },
  },
};
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <div
    v-if="parentContactName"
    class="my-4 relative p-2.5 border rounded-[4px] text-n-slate-12 border-n-weak bg-n-background"
  >
    <h5 class="text-base font-medium text-n-slate-12">
      {{ $t('MERGE_CONTACTS.SUMMARY.TITLE') }}
    </h5>
    <ul class="ms-0 list-none">
      <li>
        <span class="inline-block me-1">❌</span>
        <span
          v-dompurify-html="
            $t('MERGE_CONTACTS.SUMMARY.DELETE_WARNING', {
              primaryContactName,
            })
          "
        />
      </li>
      <li>
        <span class="inline-block me-1">✅</span>
        <span
          v-dompurify-html="
            $t('MERGE_CONTACTS.SUMMARY.ATTRIBUTE_WARNING', {
              primaryContactName,
              parentContactName,
            })
          "
        />
      </li>
      <li class="ms-6">
        <span>{{ $t('MERGE_CONTACTS.SUMMARY.CARRIED_OVER') }}</span>
      </li>
    </ul>
    <p class="mt-2 mb-0 text-sm font-medium text-n-amber-11">
      {{ $t('MERGE_CONTACTS.SUMMARY.IRREVERSIBLE') }}
    </p>
  </div>
</template>
