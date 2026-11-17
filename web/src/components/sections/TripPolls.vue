<script setup lang="ts">
import { computed, ref } from 'vue'
import { PhCalendarCheck, PhChartBar, PhCheck, PhLock, PhMapPin, PhPlus, PhTrash } from '@phosphor-icons/vue'
import PollDialog from '../PollDialog.vue'
import UnlockNote from '../UnlockNote.vue'
import type { Poll } from '@/lib/model'
import { formatDay, formatTime } from '@/lib/dates'
import { approvePoll, closePoll, deleteItem, vote } from '@/lib/writes'
import { useTripContext } from '@/composables/tripContext'

/** Polls (PollListView). Anyone votes; starting a poll is part of the full unlock; the owner closes and approves. */
const { trip, content, name, uid, isOwner, isUnlocked } = useTripContext()
const { polls, members } = content

const eligible = computed(() => new Set(members.value.map((m) => m.uid)))
const counted = (poll: Poll) => Object.entries(poll.votes).filter(([u]) => !eligible.value.size || eligible.value.has(u))
const countFor = (poll: Poll, option: number) => counted(poll).filter(([, o]) => o === option).length
const total = (poll: Poll) => counted(poll).length
function leading(poll: Poll): number[] {
  const counts = poll.options.map((_, i) => countFor(poll, i))
  const top = Math.max(0, ...counts)
  return top > 0 ? poll.options.map((_, i) => i).filter((i) => counts[i] === top) : []
}

const open = computed(() => polls.value.filter((p) => !p.isClosed).sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime()))
const closed = computed(() => polls.value.filter((p) => p.isClosed).sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime()))

const dialogOpen = ref(false)
const showLock = ref(false)
const error = ref<string | null>(null)

function start() {
  if (isUnlocked.value) dialogOpen.value = true
  else showLock.value = true
}

async function run(action: () => Promise<void>) {
  error.value = null
  try {
    await action()
  } catch (err) {
    console.error(err)
    error.value = 'Couldn’t save. Check your connection and try again.'
  }
}

const cast = (poll: Poll, option: number) => run(() => vote(trip.value.id, poll, option, uid.value))
const close = (poll: Poll) => run(() => closePoll(trip.value.id, poll.id))
const approve = (poll: Poll) => run(() => approvePoll(trip.value.id, poll, trip.value.startDate, uid.value))
function remove(poll: Poll) {
  if (window.confirm('Delete this poll?')) void run(() => deleteItem(trip.value.id, 'polls', poll.id))
}
</script>

<template>
  <div class="mx-auto max-w-3xl space-y-5">
    <div class="flex items-center justify-between gap-3">
      <p class="text-sm text-zinc-500">Decide together. Tap an option to vote; tap it again to take your vote back.</p>
      <button class="btn-primary shrink-0" @click="start">
        <PhLock v-if="!isUnlocked" class="size-4" /><PhPlus v-else class="size-4" /> Poll
      </button>
    </div>
    <UnlockNote v-if="showLock && !isUnlocked" reason="Starting polls is part of the full unlock. Everyone can still vote." />
    <p v-if="error" class="text-sm text-danger">{{ error }}</p>

    <div v-if="!polls.length" class="sticker-card-trip p-8 text-center">
      <PhChartBar class="mx-auto size-10 text-trip-500" />
      <p class="mt-3 font-display text-2xl font-bold uppercase">No polls yet</p>
      <p class="mt-1 text-sm text-zinc-500">Ask the group where to eat, which beach, or propose an activity.</p>
    </div>

    <template v-for="group in [{ title: 'Open', list: open }, { title: 'Closed', list: closed }]" :key="group.title">
      <section v-if="group.list.length">
        <h2 class="tracked-label mb-2">{{ group.title }}</h2>
        <ul class="space-y-3">
          <li v-for="poll in group.list" :key="poll.id" class="sticker-card-trip p-4">
            <div class="flex items-start gap-3">
              <div class="min-w-0 flex-1">
                <p v-if="poll.kind === 'activityProposal'" class="tracked-label text-trip-500">Proposed activity</p>
                <p class="text-lg font-semibold">{{ poll.question }}</p>
                <p class="text-xs text-zinc-500">
                  by {{ name(poll.createdByUID) }} · {{ total(poll) }} {{ total(poll) === 1 ? 'vote' : 'votes' }}
                </p>
                <p v-if="poll.kind === 'activityProposal' && (poll.location || poll.proposedDate)" class="mt-1 flex flex-wrap gap-x-3 text-sm text-zinc-600">
                  <span v-if="poll.location" class="flex items-center gap-1"><PhMapPin class="size-4 text-trip-500" /> {{ poll.location }}</span>
                  <span v-if="poll.proposedDate" class="flex items-center gap-1"><PhCalendarCheck class="size-4 text-trip-500" /> {{ formatDay(poll.proposedDate) }}, {{ formatTime(poll.proposedDate) }}</span>
                </p>
              </div>
              <button v-if="isOwner || poll.createdByUID === uid" class="icon-btn size-8 shrink-0" aria-label="Delete poll" @click="remove(poll)"><PhTrash class="size-4" /></button>
            </div>

            <ul class="mt-3 space-y-2">
              <li v-for="(option, i) in poll.options" :key="i">
                <button
                  class="relative w-full overflow-hidden rounded-xl border px-3 py-2.5 text-left transition"
                  :class="[poll.votes[uid] === i ? 'border-trip-500' : 'border-trip-border', poll.isClosed ? 'cursor-default' : 'hover:bg-trip-50']"
                  :disabled="poll.isClosed"
                  :aria-pressed="poll.votes[uid] === i"
                  @click="cast(poll, i)"
                >
                  <span class="absolute inset-y-0 left-0 bg-trip-100 transition-all" :style="{ width: `${total(poll) ? (countFor(poll, i) / total(poll)) * 100 : 0}%` }" />
                  <span class="relative flex items-center gap-2">
                    <PhCheck v-if="poll.votes[uid] === i" class="size-4 text-trip-500" weight="bold" />
                    <span class="flex-1 font-medium" :class="poll.isClosed && leading(poll).includes(i) && 'text-trip-700'">{{ option }}</span>
                    <span class="text-sm text-zinc-600">{{ countFor(poll, i) }}</span>
                  </span>
                </button>
              </li>
            </ul>

            <div v-if="isOwner && !poll.isClosed" class="mt-3 flex flex-wrap gap-2">
              <button v-if="poll.kind === 'activityProposal'" class="btn-primary px-3 py-1.5 text-sm" @click="approve(poll)">Add to itinerary</button>
              <button class="btn-secondary px-3 py-1.5 text-sm" @click="close(poll)">Close vote</button>
            </div>
          </li>
        </ul>
      </section>
    </template>

    <PollDialog v-model:open="dialogOpen" />
  </div>
</template>
