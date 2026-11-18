<script setup lang="ts">
import { computed, ref } from 'vue'
import { useRoute } from 'vue-router'
import { PhMagnifyingGlass, PhPlus, PhTicket } from '@phosphor-icons/vue'
import AccountMenu from './AccountMenu.vue'
import JoinTripDialog from './JoinTripDialog.vue'
import TripFormDialog from './TripFormDialog.vue'
import type { Trip } from '@/lib/model'
import { formatRange, startOfDay, tripStatus } from '@/lib/dates'
import { freeTripLimit } from '@/lib/writes'
import { useAuthStore } from '@/stores/auth'
import { useTripsStore } from '@/stores/trips'

/**
 * Every trip, newest plans first. The left column on desktop, and the whole
 * home page on phones (`page`), where the brand and account live in the top bar instead.
 */
defineProps<{ page?: boolean }>()

const authStore = useAuthStore()
const tripsStore = useTripsStore()
const route = useRoute()
const creating = ref(false)
const joining = ref(false)
const query = ref('')

const today = startOfDay(new Date())
const matches = (trip: Trip) => {
  const q = query.value.trim().toLowerCase()
  return !q || trip.name.toLowerCase().includes(q) || trip.location.toLowerCase().includes(q)
}
const current = computed(() =>
  tripsStore.trips
    .filter((t) => startOfDay(t.endDate) >= today && matches(t))
    .sort((a, b) => a.startDate.getTime() - b.startDate.getTime()),
)
const past = computed(() => tripsStore.trips.filter((t) => startOfDay(t.endDate) < today && matches(t)))
const sections = computed(() =>
  [
    { title: 'Upcoming', trips: current.value },
    { title: 'Past Trips', trips: past.value },
  ].filter((s) => s.trips.length),
)
const selectedId = computed(() => (route.name === 'trip' ? String(route.params.id) : null))
</script>

<template>
  <div class="flex h-full min-h-0 flex-col">
    <!-- Brand (desktop sidebar only) -->
    <div v-if="!page" class="flex items-center gap-2 px-5 pt-5 pb-3">
      <RouterLink to="/" class="flex items-center gap-2">
        <img src="/images/logo-agdayo.webp" alt="Agdayo" width="848" height="496" class="h-9 w-auto" />
      </RouterLink>
      <span class="rounded-pill bg-mint px-1.5 py-0.5 text-[10px] font-bold tracking-wider text-mint-text uppercase">Beta</span>
    </div>

    <div class="space-y-3 px-4" :class="page ? 'pt-5' : ''">
      <div v-if="page">
        <h1 class="display-title text-5xl">My Trips</h1>
      </div>
      <div class="flex gap-2">
        <button class="btn-primary flex-1" @click="creating = true"><PhPlus class="size-4" /> Create Trip</button>
        <button class="btn-secondary" @click="joining = true"><PhTicket class="size-4" /> Join with Code</button>
      </div>
      <div v-if="tripsStore.trips.length > 4" class="relative">
        <label class="sr-only" for="trip-search">Search trips</label>
        <PhMagnifyingGlass class="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-zinc-400" />
        <input id="trip-search" v-model="query" type="search" class="input py-2 pl-9 text-sm" placeholder="Search trips" />
      </div>
      <p v-if="!tripsStore.isUnlocked && !tripsStore.loading" class="text-xs text-zinc-500">
        Free Version: {{ Math.min(tripsStore.ownedTrips.length, freeTripLimit) }} of {{ freeTripLimit }} trips used. Trips you join don’t count.
      </p>
    </div>

    <!-- Trips -->
    <nav class="mt-3 min-h-0 flex-1 overflow-y-auto px-3 pb-4" aria-label="Trips">
      <div v-if="tripsStore.loading" class="space-y-2 px-1">
        <div v-for="n in 4" :key="n" class="h-16 animate-pulse rounded-dense bg-card-surface" />
      </div>

      <div v-else-if="tripsStore.trips.length === 0" class="mx-1 rounded-dense border border-dashed border-secondary p-5 text-center text-sm text-zinc-500">
        No trips yet. Make one, or join a friend’s with their code.
      </div>

      <p v-else-if="sections.length === 0" class="px-2 py-4 text-sm text-zinc-500">No trips match “{{ query }}”.</p>

      <section v-for="section in sections" :key="section.title" class="mt-2 first:mt-0">
        <h2 class="tracked-label px-2 pt-2 pb-1.5">{{ section.title }}</h2>
        <ul class="space-y-1">
          <li v-for="(trip, n) in section.trips" :key="trip.id" class="rise" :style="{ '--i': n }">
            <RouterLink
              :to="{ name: 'trip', params: { id: trip.id } }"
              :data-theme="trip.theme"
              class="press group flex items-center gap-3 rounded-dense border px-3 py-2.5 transition"
              :class="selectedId === trip.id ? 'border-trip-200 bg-white shadow-[2px_2px_0_0_var(--trip-200)]' : 'border-transparent hover:bg-black/[0.04]'"
              :aria-current="selectedId === trip.id ? 'page' : undefined"
            >
              <span
                class="flex size-10 shrink-0 items-center justify-center rounded-xl font-display text-xl font-bold uppercase"
                :class="tripStatus(trip.startDate, trip.endDate).kind === 'active' ? 'bg-trip-700 text-white' : 'bg-trip-100 text-trip-700'"
              >
                {{ trip.name.trim().charAt(0) || '?' }}
              </span>
              <span class="min-w-0 flex-1">
                <span class="flex items-center gap-1.5">
                  <span class="truncate font-semibold">{{ trip.name }}</span>
                  <span v-if="tripStatus(trip.startDate, trip.endDate).kind === 'active'" class="size-2 shrink-0 rounded-full bg-success" title="Happening now" />
                </span>
                <span v-if="tripStatus(trip.startDate, trip.endDate).kind === 'active'" class="block truncate text-xs font-semibold text-mint-text">
                  {{ tripStatus(trip.startDate, trip.endDate).label.replace('Active · ', '') }}<template v-if="trip.location"> · {{ trip.location }}</template>
                </span>
                <span v-else class="block truncate text-xs text-zinc-500">
                  {{ formatRange(trip.startDate, trip.endDate) }}<template v-if="trip.location"> · {{ trip.location }}</template>
                </span>
                <span v-if="trip.ownerUID !== authStore.user?.uid" class="mt-0.5 block text-[10px] font-semibold tracking-wider text-zinc-400 uppercase">Shared with you</span>
              </span>
            </RouterLink>
          </li>
        </ul>
      </section>
    </nav>

    <!-- Account (desktop sidebar only) -->
    <div v-if="!page" class="border-t border-black/5 p-3">
      <AccountMenu full />
    </div>

    <TripFormDialog v-model:open="creating" />
    <JoinTripDialog v-model:open="joining" />
  </div>
</template>
