<script setup lang="ts">
import { PhLock } from '@phosphor-icons/vue'
import { config } from '@/config'

/** There's no buying on the web: unlocking only happens in the iPhone app. */
defineProps<{ reason: string }>()
const appStoreUrl = config.appStoreUrl
</script>

<template>
  <div class="flex items-start gap-3 rounded-dense border border-blush bg-blush/40 p-4">
    <PhLock class="mt-0.5 size-5 shrink-0 text-maroon" />
    <div class="text-sm">
      <p class="font-medium text-ink">{{ reason }}</p>
      <p class="mt-1 text-zinc-600">
        Unlock in the Agdayo iPhone app, then it works here too.
        <a v-if="appStoreUrl" :href="appStoreUrl" target="_blank" rel="noopener" class="font-semibold text-maroon underline">Get the app</a>
      </p>
    </div>
  </div>
</template>
