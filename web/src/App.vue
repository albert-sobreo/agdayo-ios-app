<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import AppHeader from '@/components/AppHeader.vue'
import TripSidebar from '@/components/TripSidebar.vue'
import { useAuthStore } from '@/stores/auth'

const authStore = useAuthStore()
const route = useRoute()
/** Signed-in pages get the app frame: the trip sidebar on desktop, a top bar on phones. */
const framed = computed(() => !!authStore.user && !route.meta.public)
</script>

<template>
  <div v-if="!authStore.ready" class="flex min-h-dvh items-center justify-center">
    <img src="/images/logo-agdayo.webp" alt="Agdayo" width="848" height="496" class="h-16 w-auto animate-pulse" />
  </div>

  <div v-else-if="framed" class="lg:flex lg:h-dvh lg:overflow-hidden">
    <aside class="hidden w-80 shrink-0 border-r border-black/5 bg-card-surface/60 lg:block xl:w-[22rem]">
      <TripSidebar />
    </aside>
    <AppHeader />
    <div id="main-scroll" class="min-w-0 lg:flex-1 lg:overflow-y-auto">
      <RouterView />
    </div>
  </div>

  <RouterView v-else />
</template>
