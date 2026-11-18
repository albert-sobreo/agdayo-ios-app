<script setup lang="ts">
import { computed, ref } from 'vue'
import { useRoute } from 'vue-router'
import { PhPlus, PhSquaresFour } from '@phosphor-icons/vue'
import TripFormDialog from './TripFormDialog.vue'
import { startOfDay, tripStatus } from '@/lib/dates'
import { useTripsStore } from '@/stores/trips'

/** The trip list folded into a slim rail, so the map view gets the room. */
const tripsStore = useTripsStore()
const route = useRoute()
const creating = ref(false)

const upcoming = computed(() => {
  const today = startOfDay(new Date())
  return tripsStore.trips
    .filter((t) => startOfDay(t.endDate) >= today)
    .sort((a, b) => a.startDate.getTime() - b.startDate.getTime())
    .slice(0, 6)
})
const selectedId = computed(() => (route.name === 'trip' ? String(route.params.id) : null))
</script>

<template>
  <nav class="flex h-full flex-col items-center gap-3 bg-ink py-5" aria-label="My Trips">
    <RouterLink to="/" class="font-display text-2xl font-bold text-blush" aria-label="My Trips">AG</RouterLink>
    <RouterLink
      v-for="trip in upcoming"
      :key="trip.id"
      :to="{ name: 'trip', params: { id: trip.id }, query: selectedId === trip.id ? route.query : { tab: 'map' } }"
      :data-theme="trip.theme"
      :title="trip.name"
      :aria-label="trip.name + (tripStatus(trip.startDate, trip.endDate).kind === 'active' ? ', happening now' : '')"
      :aria-current="selectedId === trip.id ? 'page' : undefined"
      class="flex size-12 shrink-0 items-center justify-center rounded-2xl font-display text-[22px] font-bold uppercase transition"
      :class="selectedId === trip.id ? 'bg-trip-700 text-white outline-2 outline-offset-3 outline-trip-200' : 'bg-trip-100 text-trip-700 hover:opacity-85'"
    >{{ trip.name.trim().charAt(0) || '?' }}</RouterLink>
    <span class="h-px w-7 bg-zinc-700" />
    <RouterLink to="/" class="flex size-12 items-center justify-center rounded-2xl border border-zinc-600 text-zinc-200 transition hover:bg-white/10" aria-label="My Trips" title="My Trips">
      <PhSquaresFour class="size-5" />
    </RouterLink>
    <button class="flex size-12 items-center justify-center rounded-2xl bg-white text-ink transition hover:bg-zinc-200" aria-label="Create Trip" title="Create Trip" @click="creating = true">
      <PhPlus class="size-5" weight="bold" />
    </button>
    <TripFormDialog v-model:open="creating" />
  </nav>
</template>
