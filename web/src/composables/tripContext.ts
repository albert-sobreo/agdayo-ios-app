import { computed, inject, provide, type ComputedRef, type InjectionKey } from 'vue'
import type { useTripContent } from './useTripContent'
import type { Trip } from '@/lib/model'
import { useAuthStore } from '@/stores/auth'
import { useTripsStore } from '@/stores/trips'

export type TripContent = ReturnType<typeof useTripContent>

export interface TripContext {
  trip: ComputedRef<Trip>
  content: TripContent
  /** Members with display names, the signed-in person first. */
  people: ComputedRef<{ uid: string; name: string }[]>
  name: (uid: string | null | undefined) => string
  uid: ComputedRef<string>
  isOwner: ComputedRef<boolean>
  /** The full unlock: bought in the iPhone app (or the app was bought back when it was paid). */
  isUnlocked: ComputedRef<boolean>
}

const key: InjectionKey<TripContext> = Symbol('trip')

export function provideTripContext(trip: ComputedRef<Trip | undefined>, content: TripContent): TripContext {
  const authStore = useAuthStore()
  const tripsStore = useTripsStore()
  const uid = computed(() => authStore.user?.uid ?? '')
  const name = (id: string | null | undefined) => {
    if (!id) return 'Someone'
    if (id === uid.value) return 'You'
    return content.profiles.value[id]?.displayName || 'Traveler'
  }
  const people = computed(() => {
    const uids = content.members.value.map((m) => m.uid)
    if (uid.value && !uids.includes(uid.value)) uids.unshift(uid.value)
    return uids
      .sort((a, b) => (a === uid.value ? -1 : b === uid.value ? 1 : name(a).localeCompare(name(b))))
      .map((id) => ({ uid: id, name: name(id) }))
  })
  const context: TripContext = {
    trip: trip as ComputedRef<Trip>,
    content,
    people,
    name,
    uid,
    isOwner: computed(() => trip.value?.ownerUID === uid.value),
    isUnlocked: computed(() => tripsStore.isUnlocked),
  }
  provide(key, context)
  return context
}

export function useTripContext(): TripContext {
  const context = inject(key)
  if (!context) throw new Error('useTripContext needs a TripView above it')
  return context
}
