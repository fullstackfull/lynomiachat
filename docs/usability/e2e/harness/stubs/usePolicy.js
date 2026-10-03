import { ref } from 'vue';

// Switched by the journey that checks an agent sees no cross-module action.
export const permissions = ref(['administrator']);

export const usePolicy = () => ({
  checkPermissions: required =>
    !required?.length ||
    required.some(permission => permissions.value.includes(permission)),
  checkInstallationType: () => true,
  isFeatureFlagEnabled: () => true,
  shouldShow: () => true,
  shouldShowPaywall: () => false,
});
