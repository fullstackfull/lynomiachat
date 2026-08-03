<script setup>
import { onMounted } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';

const accountId = useMapGetter('getCurrentAccountId');

onMounted(() => {
  window.location.href =
    `https://lynomia.com/admin/subscriptions/${accountId.value}`;
});
</script>

<template>
  <div>Redirecting...</div>
</template>
