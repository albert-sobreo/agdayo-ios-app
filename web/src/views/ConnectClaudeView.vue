<script setup lang="ts">
import { PhCaretLeft } from '@phosphor-icons/vue'
import ConnectClaude from '@/components/ConnectClaude.vue'
</script>

<template>
  <main class="px-4 pt-4 pb-24 lg:px-8 lg:pt-8">
    <RouterLink to="/" class="btn-ghost -ml-3 mb-2 lg:hidden"><PhCaretLeft class="size-4" /> My trips</RouterLink>
    <ConnectClaude />
  </main>
</template>
