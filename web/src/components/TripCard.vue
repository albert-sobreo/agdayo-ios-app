<script setup lang="ts">
import { computed } from 'vue'
import { PhMapPin } from '@phosphor-icons/vue'
import type { Trip } from '@/lib/model'
import { formatRange, tripStatus } from '@/lib/dates'

const props = defineProps<{ trip: Trip; shared: boolean }>()
const status = computed(() => tripStatus(props.trip.startDate, props.trip.endDate))
</script>

<template>
  <RouterLink
    :to="{ name: 'trip', params: { id: trip.id } }"
    :data-theme="trip.theme"
    class="sticker-card-trip group block overflow-hidden rounded-card-sm transition hover:-translate-y-0.5"
  >
    <div class="bg-trip-50 px-5 pt-5 pb-4">
      <div class="flex items-center justify-between gap-2">
        <span
          class="rounded-pill px-2 py-0.5 text-[11px] font-bold tracking-wider uppercase"
          :class="status.kind === 'active' ? 'bg-mint text-mint-text' : status.kind === 'past' ? 'bg-zinc-100 text-zinc-500' : 'bg-trip-100 text-ink/70'"
        >{{ status.label }}</span>
        <span v-if="shared" class="text-[11px] font-semibold tracking-wider text-zinc-500 uppercase">Shared with you</span>
      </div>
      <h3 class="display-title mt-3 line-clamp-2 text-4xl">{{ trip.name }}</h3>
      <p class="mt-1 flex items-center gap-1 truncate text-sm text-zinc-600">
        <PhMapPin class="size-3.5 shrink-0 text-trip-500" /> {{ trip.location || 'No location yet' }}
      </p>
    </div>
    <div class="flex items-center justify-between bg-white px-5 py-3 text-sm">
      <span class="font-medium text-zinc-700">{{ formatRange(trip.startDate, trip.endDate) }}</span>
      <span class="size-2.5 rounded-full bg-trip-500" />
    </div>
  </RouterLink>
</template>
