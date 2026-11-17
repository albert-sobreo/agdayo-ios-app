<script setup lang="ts">
import { computed, ref, watchEffect } from 'vue'
import { useRouter } from 'vue-router'
import { PhPlus, PhSuitcaseRolling } from '@phosphor-icons/vue'
import TripSidebar from '@/components/TripSidebar.vue'
import TripFormDialog from '@/components/TripFormDialog.vue'
import { useIsDesktop } from '@/composables/useIsDesktop'
import { startOfDay } from '@/lib/dates'
import { useAuthStore } from '@/stores/auth'
import { useTripsStore } from '@/stores/trips'

/**
 * Home. On phones it's the trip list. On desktop the list is already in the
 * sidebar, so this opens the trip happening now or coming up next.
 */
const authStore = useAuthStore()
const tripsStore = useTripsStore()
const router = useRouter()
const isDesktop = useIsDesktop()
const creating = ref(false)

const nextTrip = computed(() => {
  const today = startOfDay(new Date())
  return tripsStore.trips
    .filter((t) => startOfDay(t.endDate) >= today)
    .sort((a, b) => a.startDate.getTime() - b.startDate.getTime())[0]
})

watchEffect(() => {
  if (isDesktop.value && !tripsStore.loading && nextTrip.value) {
    void router.replace({ name: 'trip', params: { id: nextTrip.value.id } })
  }
})

const firstName = computed(() => (tripsStore.profile?.displayName || authStore.user?.displayName || '').split(' ')[0])
</script>

<template>
  <TripSidebar v-if="!isDesktop" page class="pb-10" />

  <main v-else-if="!tripsStore.loading && !nextTrip" class="flex h-full items-center justify-center p-10">
    <div class="max-w-md text-center">
      <span class="mx-auto flex size-20 items-center justify-center rounded-card-sm bg-blush text-maroon">
        <PhSuitcaseRolling class="size-10" />
      </span>
      <h1 class="display-title mt-6 text-6xl">{{ firstName ? `Hi, ${firstName}` : 'Welcome' }}</h1>
      <p class="mt-3 text-zinc-600">
        {{ tripsStore.trips.length ? 'Pick a trip on the left to see its plan.' : 'Plan your first trip, or join a friend’s with their invite code.' }}
      </p>
      <button class="btn-primary mt-6" @click="creating = true"><PhPlus class="size-4" /> New trip</button>
    </div>
    <TripFormDialog v-model:open="creating" />
  </main>
</template>
