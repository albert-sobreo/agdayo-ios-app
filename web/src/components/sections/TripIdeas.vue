<script setup lang="ts">
import { computed, ref } from 'vue'
import { PhCalendarPlus, PhCheckCircle, PhLightbulb, PhLink, PhLock, PhMapPin, PhPencilSimple, PhPlus, PhThumbsUp } from '@phosphor-icons/vue'
import IdeaDialog from '../IdeaDialog.vue'
import UnlockNote from '../UnlockNote.vue'
import type { Idea } from '@/lib/model'
import { planIdea, toggleIdeaLike } from '@/lib/writes'
import { useTripContext } from '@/composables/tripContext'

/**
 * Ideas (IdeaListView): places and things the group wants to do. Everyone can 👍 them,
 * adding one is part of the full unlock, and the owner adds the keepers to the itinerary.
 */
const { trip, content, name, uid, isOwner, isUnlocked } = useTripContext()
const { ideas, activities } = content

const sorted = computed(() =>
  [...ideas.value].sort((a, b) => Number(a.isPlanned) - Number(b.isPlanned) || b.likedBy.length - a.likedBy.length || b.createdAt.getTime() - a.createdAt.getTime()),
)

const dialog = ref<{ open: boolean; idea?: Idea }>({ open: false })
const showLock = ref(false)
const notice = ref<string | null>(null)
const error = ref<string | null>(null)

function add() {
  if (isUnlocked.value) dialog.value = { open: true }
  else showLock.value = true
}

async function like(idea: Idea) {
  error.value = null
  try {
    await toggleIdeaLike(trip.value.id, idea, uid.value)
  } catch (err) {
    console.error(err)
    error.value = 'Couldn’t save. Check your connection and try again.'
  }
}

async function plan(idea: Idea) {
  error.value = null
  try {
    await planIdea(trip.value.id, idea, activities.value, trip.value, uid.value)
    notice.value = `${idea.title} is on the itinerary. Change its time from there.`
  } catch (err) {
    console.error(err)
    error.value = 'Couldn’t add it. Check your connection and try again.'
  }
}
</script>

<template>
  <div class="mx-auto max-w-3xl space-y-5">
    <div class="flex items-center justify-between gap-3">
      <p class="text-sm text-zinc-500">Save places and things the group wants to do. Everyone can 👍 them, and the trip owner adds the ones that make the itinerary.</p>
      <button class="btn-primary shrink-0" @click="add">
        <PhLock v-if="!isUnlocked" class="size-4" /><PhPlus v-else class="size-4" /> Idea
      </button>
    </div>
    <UnlockNote v-if="showLock && !isUnlocked" reason="Adding ideas is part of the full unlock. Everyone can still 👍 them." />
    <p v-if="notice" class="rounded-dense bg-mint p-3 text-sm text-mint-text">{{ notice }}</p>
    <p v-if="error" class="text-sm text-danger">{{ error }}</p>

    <div v-if="!ideas.length" class="sticker-card-trip p-8 text-center">
      <PhLightbulb class="mx-auto size-10 text-trip-500" />
      <p class="mt-3 font-display text-2xl font-bold uppercase">No ideas yet</p>
    </div>

    <ul class="space-y-3">
      <li v-for="idea in sorted" :key="idea.id" class="sticker-card-trip p-4" :class="idea.isPlanned && 'opacity-70'">
        <div class="flex items-start gap-3">
          <div class="min-w-0 flex-1">
            <p class="flex items-center gap-2 text-lg font-semibold">
              <span class="truncate">{{ idea.title }}</span>
              <span v-if="idea.isPlanned" class="flex shrink-0 items-center gap-1 rounded-pill bg-mint px-1.5 py-0.5 text-[10px] font-bold tracking-wider text-mint-text uppercase"><PhCheckCircle class="size-3" weight="fill" /> Planned</span>
            </p>
            <p class="text-xs text-zinc-500">Added by {{ name(idea.addedByUID) }}</p>
            <p v-if="idea.location" class="mt-1 flex items-center gap-1 text-sm text-zinc-600"><PhMapPin class="size-4 shrink-0 text-trip-500" /> {{ idea.location }}</p>
            <p v-if="idea.note" class="mt-1 text-sm whitespace-pre-line text-zinc-700">{{ idea.note }}</p>
            <a v-if="idea.link" :href="idea.link" target="_blank" rel="noopener" class="mt-1 flex items-center gap-1 truncate text-sm font-medium text-trip-700 underline"><PhLink class="size-4 shrink-0" /> {{ idea.link.replace(/^https?:\/\//, '') }}</a>
          </div>
          <button v-if="isOwner || idea.addedByUID === uid" class="icon-btn size-8 shrink-0" aria-label="Edit idea" @click="dialog = { open: true, idea }"><PhPencilSimple class="size-4" /></button>
        </div>
        <div class="mt-3 flex flex-wrap items-center gap-2">
          <button
            class="flex items-center gap-1.5 rounded-full border px-3 py-1 text-sm font-medium transition"
            :class="idea.likedBy.includes(uid) ? 'border-trip-500 bg-trip-100 text-trip-700' : 'border-trip-border bg-white hover:bg-trip-50'"
            :aria-pressed="idea.likedBy.includes(uid)"
            @click="like(idea)"
          >
            <PhThumbsUp class="size-4" :weight="idea.likedBy.includes(uid) ? 'fill' : 'regular'" /> {{ idea.likedBy.length }}
          </button>
          <button v-if="isOwner && !idea.isPlanned" class="btn-secondary px-3 py-1 text-sm" @click="plan(idea)"><PhCalendarPlus class="size-4" /> Add to itinerary</button>
        </div>
      </li>
    </ul>

    <IdeaDialog v-model:open="dialog.open" :idea="dialog.idea" />
  </div>
</template>
