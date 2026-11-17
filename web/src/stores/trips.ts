import { defineStore } from 'pinia'
import { computed, ref, watch } from 'vue'
import { doc, onSnapshot, type Unsubscribe } from 'firebase/firestore'
import { db } from '@/firebase'
import { toTrip, toUserProfile, type Trip, type UserProfile } from '@/lib/model'
import { freeTripLimit } from '@/lib/writes'
import { useAuthStore } from './auth'

/**
 * The signed-in person's trips, live. Like the app (MyTripsLiveSync), the list
 * comes from users/{uid}.memberOfTripIDs, and each trip document is listened to.
 */
export const useTripsStore = defineStore('trips', () => {
  const authStore = useAuthStore()
  const profile = ref<UserProfile | null>(null)
  const tripsById = ref<Record<string, Trip>>({})
  const loading = ref(true)
  const pending = ref(new Set<string>())

  let userUnsub: Unsubscribe | null = null
  const tripUnsubs = new Map<string, Unsubscribe>()

  function stopAll() {
    userUnsub?.()
    userUnsub = null
    tripUnsubs.forEach((unsub) => unsub())
    tripUnsubs.clear()
    tripsById.value = {}
    profile.value = null
    pending.value = new Set()
  }

  function syncTripListeners(ids: string[]) {
    const wanted = new Set(ids)
    for (const [id, unsub] of tripUnsubs) {
      if (!wanted.has(id)) {
        unsub()
        tripUnsubs.delete(id)
        delete tripsById.value[id]
      }
    }
    for (const id of wanted) {
      if (tripUnsubs.has(id)) continue
      pending.value.add(id)
      tripUnsubs.set(
        id,
        onSnapshot(
          doc(db, 'trips', id),
          (snapshot) => {
            pending.value.delete(id)
            const trip = snapshot.exists() ? toTrip(snapshot.id, snapshot.data()) : null
            if (trip) tripsById.value[id] = trip
            else if (!snapshot.metadata.fromCache) delete tripsById.value[id]
            if (pending.value.size === 0) loading.value = false
          },
          () => {
            // No access any more (removed from the trip) or it was deleted.
            pending.value.delete(id)
            delete tripsById.value[id]
            if (pending.value.size === 0) loading.value = false
          },
        ),
      )
    }
    if (wanted.size === 0) loading.value = false
  }

  watch(
    () => authStore.user?.uid,
    (uid) => {
      stopAll()
      if (!uid) return
      loading.value = true
      userUnsub = onSnapshot(
        doc(db, 'users', uid),
        (snapshot) => {
          profile.value = toUserProfile(uid, snapshot.data())
          syncTripListeners(profile.value.memberOfTripIDs)
        },
        (error) => {
          console.warn('Could not load your trips', error)
          loading.value = false
        },
      )
    },
    { immediate: true },
  )

  const trips = computed(() => Object.values(tripsById.value).sort((a, b) => b.startDate.getTime() - a.startDate.getTime()))
  const ownedTrips = computed(() => trips.value.filter((trip) => trip.ownerUID === authStore.user?.uid))

  /**
   * Whether this person has the full version. The Worker sets users/{uid}.unlocked
   * after checking an App Store purchase. Until that exists, the app's per-trip
   * ownerUnlocked flag is used the same way the Worker does: a trip without the
   * flag was made while the app was paid.
   */
  const isUnlocked = computed(
    () => profile.value?.unlocked === true || ownedTrips.value.some((trip) => trip.ownerUnlocked !== false),
  )

  const canCreateTrip = computed(() => isUnlocked.value || ownedTrips.value.length < freeTripLimit)

  return { profile, trips, ownedTrips, loading, isUnlocked, canCreateTrip, trip: (id: string) => tripsById.value[id] }
})
