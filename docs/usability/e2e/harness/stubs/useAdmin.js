import { ref } from 'vue';

export const isAdmin = ref(true);
export const useAdmin = () => ({ isAdmin });
