<script setup lang="ts">
import { computed, ref } from 'vue'
import { PhPlus, PhTicket } from '@phosphor-icons/vue'
import TripCard from '@/components/TripCard.vue'
import TripFormDialog from '@/components/TripFormDialog.vue'
import JoinTripDialog from '@/components/JoinTripDialog.vue'
import { startOfDay } from '@/lib/dates'
import { freeTripLimit } from '@/lib/writes'
import { useAuthStore } from '@/stores/auth'
import { useTripsStore } from '@/stores/trips'

const authStore = useAuthStore()
const tripsStore = useTripsStore()
const creating = ref(false)
const joining = ref(false)

const today = startOfDay(new Date())
const current = computed(() =>
  tripsStore.trips.filter((t) => startOfDay(t.endDate) >= today).sort((a, b) => a.startDate.getTime() - b.startDate.getTime()),
)
const past = computed(() => tripsStore.trips.filter((t) => startOfDay(t.endDate) < today))
const firstName = computed(() => (tripsStore.profile?.displayName || authStore.user?.displayName || '').split(' ')[0])
</script>

<template>
  <main class="mx-auto max-w-5xl px-4 pt-6 pb-16">
    <div class="flex flex-wrap items-end justify-between gap-4">
      <div>
        <p class="tracked-label">My trips</p>
        <h1 class="display-title mt-1 text-5xl">{{ firstName ? `Hi, ${firstName}` : 'Your trips' }}</h1>
      </div>
      <div class="flex gap-2">
        <button class="btn-secondary" @click="joining = true"><PhTicket class="size-4" /> Join</button>
        <button class="btn-primary" @click="creating = true"><PhPlus class="size-4" /> New trip</button>
      </div>
    </div>
    <p v-if="!tripsStore.isUnlocked && !tripsStore.loading" class="mt-3 text-sm text-zinc-500">
      Free version: {{ Math.min(tripsStore.ownedTrips.length, freeTripLimit) }} of {{ freeTripLimit }} trips used. Trips you join don’t count.
    </p>

    <div v-if="tripsStore.loading" class="mt-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <div v-for="n in 3" :key="n" class="h-44 animate-pulse rounded-card-sm bg-card-surface" />
    </div>

    <div v-else-if="tripsStore.trips.length === 0" class="sticker-card mt-8 rounded-card-sm p-8 text-center">
      <h2 class="font-display text-3xl font-bold text-maroon uppercase">No trips yet</h2>
      <p class="mx-auto mt-2 max-w-sm text-zinc-600">
        Make your first trip, or join one with a code from a friend. Trips you made in the iPhone app show up here once you’re signed in there with the same account.
      </p>
      <button class="btn-primary mt-5" @click="creating = true"><PhPlus class="size-4" /> New trip</button>
    </div>

    <template v-else>
      <section v-if="current.length" class="mt-8">
        <h2 class="tracked-label mb-3">Upcoming and current</h2>
        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <TripCard v-for="trip in current" :key="trip.id" :trip="trip" :shared="trip.ownerUID !== authStore.user?.uid" />
        </div>
      </section>
      <section v-if="past.length" class="mt-10">
        <h2 class="tracked-label mb-3">Past trips</h2>
        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <TripCard v-for="trip in past" :key="trip.id" :trip="trip" :shared="trip.ownerUID !== authStore.user?.uid" />
        </div>
      </section>
    </template>

    <TripFormDialog v-model:open="creating" />
    <JoinTripDialog v-model:open="joining" />
  </main>
</template>
