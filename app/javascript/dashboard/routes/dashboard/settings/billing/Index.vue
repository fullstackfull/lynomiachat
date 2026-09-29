<script setup>
import { onMounted } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import Spinner from 'shared/components/Spinner.vue';

const accountId = useMapGetter('getCurrentAccountId');

onMounted(() => {
  window.location.href = `https://lynomia.com/admin/subscriptions/${accountId.value}`;
});
</script>

<template>
  <div class="flex justify-center p-8">
    <Spinner />
  </div>
</template>
