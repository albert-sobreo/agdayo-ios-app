<script setup lang="ts">
import { computed, ref } from 'vue'
import { useRouter } from 'vue-router'
import { PhCheck, PhCopy, PhSignOut, PhUserMinus } from '@phosphor-icons/vue'
import UnlockNote from '../UnlockNote.vue'
import { freeMemberLimit, removeFromSplits, removeMember } from '@/lib/writes'
import { useTripContext } from '@/composables/tripContext'

/** Members (MembersView in the app): who's on the trip, the invite code, remove or leave. */
const { trip, content, name, uid, isOwner } = useTripContext()
const { activities, stays, transport, expenses, members, profiles } = content
const router = useRouter()

const sorted = computed(() =>
  [...members.value].sort((a, b) => (a.role === 'owner' ? -1 : b.role === 'owner' ? 1 : name(a.uid).localeCompare(name(b.uid)))),
)
const isFreeTrip = computed(() => trip.value.ownerUnlocked === false)

const copied = ref(false)
async function copyCode() {
  if (!trip.value.joinCode) return
  await navigator.clipboard.writeText(trip.value.joinCode)
  copied.value = true
  setTimeout(() => (copied.value = false), 1500)
}

const error = ref<string | null>(null)
async function kick(memberUID: string) {
  if (!window.confirm(`Remove ${name(memberUID)} from this trip? Their share of split costs goes to the others.`)) return
  error.value = null
  try {
    await removeFromSplits(trip.value.id, memberUID, { activities: activities.value, stays: stays.value, transport: transport.value, expenses: expenses.value })
    await removeMember(trip.value.id, memberUID)
  } catch (err) {
    console.error(err)
    error.value = 'Couldn’t remove them. Check your connection and try again.'
  }
}
async function leave() {
  if (!window.confirm(`Leave “${trip.value.name}”? You’ll need a new invite to come back.`)) return
  error.value = null
  try {
    await removeMember(trip.value.id, uid.value)
    await router.replace({ name: 'trips' })
  } catch (err) {
    console.error(err)
    error.value = 'Couldn’t leave the trip. Check your connection and try again.'
  }
}
</script>

<template>
  <div class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_340px]">
    <section>
      <p class="tracked-label mb-2">{{ members.length }} Member{{ members.length === 1 ? '' : 's' }}</p>
      <ul class="space-y-2">
        <li v-for="member in sorted" :key="member.uid" class="sticker-card flex items-center gap-3 px-4 py-3">
          <img
            v-if="profiles[member.uid]?.photoURL"
            :src="profiles[member.uid]?.photoURL ?? ''"
            alt=""
            class="size-10 rounded-full object-cover"
            referrerpolicy="no-referrer"
          />
          <span v-else class="flex size-10 items-center justify-center rounded-full bg-trip-100 font-bold text-trip-700">{{ name(member.uid).charAt(0) }}</span>
          <span class="min-w-0 flex-1 truncate font-semibold">{{ name(member.uid) }}</span>
          <span v-if="member.role === 'owner'" class="tracked-label">Owner</span>
          <button
            v-else-if="isOwner && member.uid !== uid"
            class="icon-btn"
            :aria-label="`Remove ${name(member.uid)}`"
            @click="kick(member.uid)"
          ><PhUserMinus class="size-4.5" /></button>
        </li>
      </ul>
      <p v-if="error" class="mt-3 text-sm text-danger">{{ error }}</p>
      <button v-if="!isOwner" class="btn-danger mt-4 -ml-2" @click="leave"><PhSignOut class="size-4" /> Leave Trip</button>
    </section>

    <aside class="space-y-3">
      <div v-if="trip.joinCode" class="rounded-card-sm border border-trip-200 bg-trip-50 p-5">
        <p class="tracked-label">Trip Invite Code</p>
        <div class="mt-2 flex items-center justify-between gap-2">
          <span class="font-display text-4xl font-semibold tracking-[0.2em] text-trip-700">{{ trip.joinCode }}</span>
          <button class="btn-secondary px-3" :aria-label="copied ? 'Copied' : 'Copy code'" @click="copyCode">
            <PhCheck v-if="copied" class="size-4 text-mint-text" /><PhCopy v-else class="size-4" />
            {{ copied ? 'Copied' : 'Copy' }}
          </button>
        </div>
        <p class="mt-3 text-sm text-zinc-600">Friends enter this code with Join with Code, in the app or on the web.</p>
      </div>
      <template v-if="isFreeTrip && members.length >= freeMemberLimit">
        <UnlockNote v-if="isOwner" :reason="`Free trips hold up to ${freeMemberLimit} people. Unlock for bigger groups.`" />
        <p v-else class="text-sm text-zinc-500">This trip is full. The owner can unlock Agdayo for bigger groups.</p>
      </template>
    </aside>
  </div>
</template>
