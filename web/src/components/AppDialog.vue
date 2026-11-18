<script setup lang="ts">
import { DialogClose, DialogContent, DialogDescription, DialogOverlay, DialogPortal, DialogRoot, DialogTitle } from 'reka-ui'
import { PhX } from '@phosphor-icons/vue'

/** A sheet from the bottom on phones and a centered card on wider screens, like the app's edit sheets. */
defineProps<{ title: string; description?: string; theme?: string }>()
const open = defineModel<boolean>('open', { required: true })
</script>

<template>
  <DialogRoot v-model:open="open">
    <DialogPortal>
      <DialogOverlay class="app-overlay fixed inset-0 z-40 bg-black/30 backdrop-blur-[2px]" />
      <DialogContent
        :data-theme="theme"
        class="app-dialog fixed inset-x-0 bottom-0 z-50 flex max-h-[92dvh] flex-col rounded-t-card-sm bg-canvas shadow-xl outline-none sm:inset-auto sm:top-1/2 sm:left-1/2 sm:w-full sm:max-w-lg sm:-translate-x-1/2 sm:-translate-y-1/2 sm:rounded-card-sm"
      >
        <div class="flex items-center justify-between gap-3 border-b border-black/5 px-5 pt-4 pb-3">
          <div class="min-w-0">
            <DialogTitle class="truncate text-lg font-semibold">{{ title }}</DialogTitle>
            <DialogDescription v-if="description" class="text-sm text-zinc-500">{{ description }}</DialogDescription>
          </div>
          <DialogClose class="icon-btn shrink-0" aria-label="Close"><PhX class="size-5" /></DialogClose>
        </div>
        <div class="flex-1 overflow-y-auto px-5 py-4">
          <slot />
        </div>
        <div v-if="$slots.footer" class="flex items-center gap-2 border-t border-black/5 px-5 py-3 pb-[max(0.75rem,env(safe-area-inset-bottom))]">
          <slot name="footer" />
        </div>
      </DialogContent>
    </DialogPortal>
  </DialogRoot>
</template>
