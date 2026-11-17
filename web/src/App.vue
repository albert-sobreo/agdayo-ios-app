<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import AppHeader from '@/components/AppHeader.vue'
import { useAuthStore } from '@/stores/auth'

const authStore = useAuthStore()
const route = useRoute()
const showHeader = computed(() => authStore.user && route.name !== 'sign-in')
</script>

<template>
  <div v-if="!authStore.ready" class="flex min-h-dvh items-center justify-center">
    <img src="/images/logo-agdayo.webp" alt="Agdayo" width="848" height="496" class="h-16 w-auto animate-pulse" />
  </div>
  <template v-else>
    <AppHeader v-if="showHeader" />
    <RouterView />
  </template>
</template>
