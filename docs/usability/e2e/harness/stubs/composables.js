import { ref } from 'vue';

export const alerts = ref([]);

export const useAlert = message => {
  alerts.value.push(message);
  const node = document.getElementById('harness-alert');
  if (node) node.textContent = message;
};

export const useTrack = () => {};
