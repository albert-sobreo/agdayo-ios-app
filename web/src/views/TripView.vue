<script setup lang="ts">
import { computed, ref, toRef } from 'vue'
import {
  DropdownMenuContent, DropdownMenuItem, DropdownMenuPortal, DropdownMenuRoot, DropdownMenuTrigger,
} from 'reka-ui'
import { PhArrowRight, PhBed, PhCheck, PhCaretLeft, PhCopy, PhPencilSimple, PhPlus, PhNote, PhUsers } from '@phosphor-icons/vue'
import ActivityDialog from '@/components/ActivityDialog.vue'
import DayNoteDialog from '@/components/DayNoteDialog.vue'
import StayDialog from '@/components/StayDialog.vue'
import TransportDialog from '@/components/TransportDialog.vue'
import TripFormDialog from '@/components/TripFormDialog.vue'
import UnlockNote from '@/components/UnlockNote.vue'
import { useTripContent } from '@/composables/useTripContent'
import type { Activity, DayNote, Stay, Transport } from '@/lib/model'
import { stayTypeNames, transportModeNames } from '@/lib/model'
import {
  combine, formatDay, formatHHmm, formatMoney, formatRange, formatShort, formatTime, isSameDay, tripDays, tripStatus,
} from '@/lib/dates'
import { iconFor, transportIcons } from '@/lib/icons'
import { freeMemberLimit } from '@/lib/writes'
import { useAuthStore } from '@/stores/auth'
import { useTripsStore } from '@/stores/trips'

const props = defineProps<{ id: string }>()
const authStore = useAuthStore()
const tripsStore = useTripsStore()

const trip = computed(() => tripsStore.trip(props.id))
const content = useTripContent(toRef(props, 'id'))
const { activities, stays, transport, dayNotes, members, profiles } = content

const isOwner = computed(() => trip.value?.ownerUID === authStore.user?.uid)
const status = computed(() => (trip.value ? tripStatus(trip.value.startDate, trip.value.endDate) : null))
const days = computed(() => (trip.value ? tripDays(trip.value.startDate, trip.value.endDate) : []))

type Entry =
  | { kind: 'activity'; time: Date; key: string; activity: Activity }
  | { kind: 'depart' | 'arrive'; time: Date; key: string; segment: Transport }
  | { kind: 'check-in' | 'check-out'; time: Date; key: string; stay: Stay }

/** Everything on the itinerary with the moment it happens, like the app's day timeline. */
const entries = computed<Entry[]>(() => {
  const list: Entry[] = []
  for (const activity of activities.value) list.push({ kind: 'activity', time: activity.date, key: `a-${activity.id}`, activity })
  for (const segment of transport.value) {
    list.push({ kind: 'depart', time: combine(segment.departureDate, segment.departureTime), key: `t-${segment.id}`, segment })
    if (segment.arrivalDate && segment.arrivalTime && !isSameDay(segment.arrivalDate, segment.departureDate)) {
      list.push({ kind: 'arrive', time: combine(segment.arrivalDate, segment.arrivalTime), key: `ta-${segment.id}`, segment })
    }
  }
  for (const stay of stays.value) {
    list.push({ kind: 'check-in', time: combine(stay.startDate, stay.checkInTime), key: `si-${stay.id}`, stay })
    list.push({ kind: 'check-out', time: combine(stay.endDate, stay.checkOutTime), key: `so-${stay.id}`, stay })
  }
  return list.sort((a, b) => a.time.getTime() - b.time.getTime())
})

const entriesOn = (day: Date) => entries.value.filter((entry) => isSameDay(entry.time, day))
const notesOn = (day: Date): DayNote[] => dayNotes.value.filter((note) => isSameDay(note.day, day))
/** Activities dated outside the trip (e.g. after its dates changed), so nothing goes missing. */
const outside = computed(() =>
  entries.value.filter((entry) => entry.kind === 'activity' && !days.value.some((day) => isSameDay(day, entry.time))),
)
const sortedStays = computed(() => [...stays.value].sort((a, b) => a.startDate.getTime() - b.startDate.getTime()))
const sortedTransport = computed(() =>
  [...transport.value].sort((a, b) => combine(a.departureDate, a.departureTime).getTime() - combine(b.departureDate, b.departureTime).getTime()),
)

function memberName(uid: string) {
  if (uid === authStore.user?.uid) return 'You'
  return profiles.value[uid]?.displayName || 'Traveler'
}
const stats = computed(() => [
  { label: 'Days', value: days.value.length },
  { label: 'Plans', value: activities.value.length },
  { label: 'Stays', value: stays.value.length },
  { label: 'People', value: members.value.length || 1 },
])
const sortedMembers = computed(() => [...members.value].sort((a, b) => (a.role === 'owner' ? -1 : b.role === 'owner' ? 1 : 0)))
const isFreeTrip = computed(() => trip.value?.ownerUnlocked === false)

const copied = ref(false)
async function copyCode() {
  if (!trip.value?.joinCode) return
  await navigator.clipboard.writeText(trip.value.joinCode)
  copied.value = true
  setTimeout(() => (copied.value = false), 1500)
}

function scrollToDay(index: number) {
  document.getElementById(`day-${index}`)?.scrollIntoView({ behavior: 'smooth', block: 'start' })
}
const todayIndex = computed(() => days.value.findIndex((day) => isSameDay(day, new Date())))

// Dialogs
const editingTrip = ref(false)
const activityDialog = ref<{ open: boolean; activity?: Activity; day?: Date }>({ open: false })
const stayDialog = ref<{ open: boolean; stay?: Stay }>({ open: false })
const transportDialog = ref<{ open: boolean; segment?: Transport; day?: Date }>({ open: false })
const noteDialog = ref<{ open: boolean; note?: DayNote; day: Date }>({ open: false, day: new Date() })

function entryIcon(entry: Entry) {
  if (entry.kind === 'activity') return iconFor(entry.activity.iconName)
  if ('segment' in entry) return transportIcons[entry.segment.mode]
  return PhBed
}

function openEntry(entry: Entry) {
  if (entry.kind === 'activity') activityDialog.value = { open: true, activity: entry.activity }
  else if ('segment' in entry) transportDialog.value = { open: true, segment: entry.segment }
  else stayDialog.value = { open: true, stay: entry.stay }
}
</script>

<template>
  <main v-if="!trip && tripsStore.loading" class="mx-auto max-w-5xl px-4 py-10">
    <div class="h-48 animate-pulse rounded-card bg-card-surface" />
  </main>

  <main v-else-if="!trip" class="mx-auto max-w-md px-4 py-20 text-center">
    <h1 class="display-title text-5xl">Trip not found</h1>
    <p class="mt-3 text-zinc-600">It may have been deleted, or you’re no longer a member.</p>
    <RouterLink to="/" class="btn-primary mt-6">Back to my trips</RouterLink>
  </main>

  <main v-else :data-theme="trip.theme" class="overflow-x-clip px-4 pt-4 pb-24 lg:px-8 lg:pt-6 xl:px-10">
    <RouterLink to="/" class="btn-ghost -ml-3 mb-2 lg:hidden"><PhCaretLeft class="size-4" /> My trips</RouterLink>

    <!-- Header -->
    <section class="sticker-card-trip overflow-hidden rounded-card">
      <div class="flex flex-col gap-6 bg-trip-50 px-5 pt-5 pb-6 sm:px-8 sm:pt-7 xl:px-10 xl:pt-8 xl:pb-8 2xl:flex-row 2xl:items-end 2xl:justify-between">
        <div class="min-w-0">
          <div class="flex items-center gap-3">
            <span
              v-if="status"
              class="rounded-pill px-2 py-0.5 text-[11px] font-bold tracking-wider uppercase"
              :class="status.kind === 'active' ? 'bg-mint text-mint-text' : status.kind === 'past' ? 'bg-zinc-100 text-zinc-500' : 'bg-trip-100 text-ink/70'"
            >{{ status.label }}</span>
            <button v-if="isOwner" class="icon-btn -my-2 ml-auto lg:ml-0" aria-label="Edit trip details" @click="editingTrip = true">
              <PhPencilSimple class="size-4.5" />
            </button>
          </div>
          <!-- Same type as iOS TripHeaderView: destination in Barlow Condensed 72pt (Regular, what the iPhone renders),
               trip name below in SemiBold 20pt with 1pt tracking -->
          <h1 class="mt-3 font-display text-6xl leading-[0.95] font-normal break-words text-trip-700 uppercase sm:text-7xl 2xl:text-8xl">{{ trip.location || trip.name }}</h1>
          <p v-if="trip.location" class="mt-1 font-display text-xl font-semibold tracking-[0.05em] break-words text-trip-700 uppercase">{{ trip.name }}</p>
          <p class="mt-2 text-zinc-600">{{ formatRange(trip.startDate, trip.endDate) }}</p>
          <p v-if="trip.tripDescription" class="mt-3 max-w-2xl text-sm whitespace-pre-line text-zinc-700">{{ trip.tripDescription }}</p>
        </div>
        <!-- At a glance -->
        <dl class="grid shrink-0 grid-cols-4 gap-2 sm:gap-3 lg:max-w-lg 2xl:max-w-none">
          <div v-for="stat in stats" :key="stat.label" class="rounded-dense border border-trip-border bg-white/70 px-3 py-2.5 text-center xl:min-w-24 xl:px-4">
            <dt class="text-[10px] font-bold tracking-wider text-zinc-500 uppercase">{{ stat.label }}</dt>
            <dd class="font-display text-3xl leading-tight font-light text-trip-700 uppercase xl:text-4xl">{{ stat.value }}</dd>
          </div>
        </dl>
      </div>
    </section>

    <!-- Day jump bar: stays in view while scrolling -->
    <nav class="sticky top-14 z-20 -mx-4 mt-4 flex gap-2 overflow-x-auto bg-canvas/90 px-4 py-2.5 backdrop-blur lg:top-0 lg:-mx-8 lg:px-8 xl:-mx-10 xl:px-10" aria-label="Days">
      <button
        v-for="(day, index) in days"
        :key="day.getTime()"
        class="shrink-0 rounded-full border px-3 py-1.5 text-sm font-medium transition"
        :class="index === todayIndex ? 'border-trip-500 bg-trip-500 text-white' : 'border-trip-border bg-white text-ink hover:bg-trip-50'"
        @click="scrollToDay(index)"
      >
        Day {{ index + 1 }} <span class="opacity-70">· {{ formatShort(day) }}</span>
      </button>
    </nav>

    <p v-if="content.error.value" class="mt-4 rounded-dense bg-danger/10 p-3 text-sm text-danger">{{ content.error.value }}</p>

    <div class="mt-4 grid grid-cols-1 gap-8 xl:grid-cols-[minmax(0,1fr)_340px] 2xl:grid-cols-[minmax(0,1fr)_380px]">
      <!-- Itinerary -->
      <div class="grid min-w-0 content-start gap-8 min-[1800px]:grid-cols-2 min-[1800px]:gap-x-10">
        <section v-for="(day, index) in days" :id="`day-${index}`" :key="day.getTime()" class="min-w-0 scroll-mt-32 lg:scroll-mt-20">
          <div class="mb-3 flex items-center justify-between gap-2">
            <div>
              <p class="tracked-label">Day {{ index + 1 }}</p>
              <h2 class="font-display text-3xl font-semibold uppercase">{{ formatDay(day) }}</h2>
            </div>
            <DropdownMenuRoot>
              <DropdownMenuTrigger class="btn-secondary px-3" :aria-label="`Add to day ${index + 1}`"><PhPlus class="size-4" /> Add</DropdownMenuTrigger>
              <DropdownMenuPortal>
                <DropdownMenuContent align="end" :side-offset="6" class="z-50 min-w-48 rounded-dense border border-secondary bg-white p-1 shadow-sticker">
                  <DropdownMenuItem class="menu-item" @select="activityDialog = { open: true, day }">Activity</DropdownMenuItem>
                  <DropdownMenuItem class="menu-item" @select="transportDialog = { open: true, day }">Transport</DropdownMenuItem>
                  <DropdownMenuItem class="menu-item" @select="stayDialog = { open: true }">Stay</DropdownMenuItem>
                  <DropdownMenuItem class="menu-item" @select="noteDialog = { open: true, day }">Note</DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenuPortal>
            </DropdownMenuRoot>
          </div>

          <button
            v-for="note in notesOn(day)"
            :key="note.id"
            class="mb-3 flex w-full items-start gap-3 rounded-dense border border-amber-200 bg-amber-50 p-3 text-left transition hover:bg-amber-100/70"
            @click="noteDialog = { open: true, note, day }"
          >
            <PhNote class="mt-0.5 size-4 shrink-0 text-amber-600" />
            <span class="min-w-0">
              <span v-if="note.title" class="block font-semibold">{{ note.title }}</span>
              <span v-if="note.content" class="block text-sm whitespace-pre-line text-zinc-700">{{ note.content }}</span>
            </span>
          </button>

          <ol v-if="entriesOn(day).length" class="relative space-y-2 before:absolute before:top-3 before:bottom-3 before:left-[calc(5.25rem-0.5px)] before:w-px before:bg-trip-200">
            <li v-for="entry in entriesOn(day)" :key="entry.key">
              <button class="group flex w-full items-start gap-3 text-left" @click="openEntry(entry)">
                <span class="w-14 shrink-0 pt-3 text-right text-xs font-semibold text-zinc-500 tabular-nums">{{ formatTime(entry.time) }}</span>
                <span class="relative z-10 mt-2 flex size-8 shrink-0 items-center justify-center rounded-full border-2 border-white bg-trip-100 text-trip-500">
                  <component
                    :is="entryIcon(entry)"
                    class="size-4"
                  />
                </span>
                <span class="sticker-card min-w-0 flex-1 px-4 py-3 transition group-hover:-translate-y-0.5">
                  <template v-if="entry.kind === 'activity'">
                    <span class="block font-semibold">{{ entry.activity.title }}</span>
                    <span v-if="entry.activity.location" class="block truncate text-sm text-zinc-500">{{ entry.activity.location }}</span>
                    <span v-if="entry.activity.activityDescription" class="mt-1 line-clamp-2 block text-sm text-zinc-600">{{ entry.activity.activityDescription }}</span>
                    <span v-if="entry.activity.cost" class="mt-2 inline-block rounded-pill bg-trip-100 px-2 py-0.5 text-xs font-semibold">
                      {{ formatMoney(entry.activity.cost, entry.activity.costCurrency ?? trip.currency) }}<template v-if="entry.activity.costNote"> · {{ entry.activity.costNote }}</template>
                    </span>
                  </template>
                  <template v-else-if="'segment' in entry">
                    <span class="block text-xs font-bold tracking-wider text-zinc-500 uppercase">
                      {{ transportModeNames[entry.segment.mode] }} · {{ entry.kind === 'depart' ? 'Departs' : 'Arrives' }}
                    </span>
                    <span class="flex flex-wrap items-center gap-x-1.5 font-semibold">
                      <span>{{ entry.segment.departureLocation }}</span>
                      <PhArrowRight class="size-4 shrink-0 text-trip-500" />
                      <span>{{ entry.segment.arrivalLocation }}</span>
                    </span>
                    <span class="block text-sm text-zinc-500">
                      <template v-if="entry.segment.arrivalTime">Arrives {{ formatHHmm(entry.segment.arrivalTime) }}</template>
                      <template v-if="entry.segment.bookingRef"> · Ref {{ entry.segment.bookingRef }}</template>
                      <template v-if="entry.segment.seatNumber"> · Seat {{ entry.segment.seatNumber }}</template>
                    </span>
                  </template>
                  <template v-else-if="'stay' in entry">
                    <span class="block text-xs font-bold tracking-wider text-zinc-500 uppercase">{{ entry.kind === 'check-in' ? 'Check in' : 'Check out' }}</span>
                    <span class="block font-semibold">{{ entry.stay.name }}</span>
                    <span v-if="entry.stay.location" class="block truncate text-sm text-zinc-500">{{ entry.stay.location }}</span>
                  </template>
                </span>
              </button>
            </li>
          </ol>
          <button
            v-else-if="!notesOn(day).length"
            class="w-full rounded-dense border border-dashed border-trip-200 p-4 text-sm text-zinc-500 transition hover:bg-trip-50"
            @click="activityDialog = { open: true, day }"
          >
            Nothing planned yet. Add an activity.
          </button>
        </section>

        <section v-if="outside.length" class="min-[1800px]:col-span-2">
          <p class="tracked-label">Outside the trip dates</p>
          <ul class="mt-2 space-y-2">
            <li v-for="entry in outside" :key="entry.key">
              <button class="sticker-card w-full px-4 py-3 text-left" @click="openEntry(entry)">
                <span class="block font-semibold">{{ entry.kind === 'activity' ? entry.activity.title : '' }}</span>
                <span class="text-sm text-zinc-500">{{ formatDay(entry.time) }}, {{ formatTime(entry.time) }}</span>
              </button>
            </li>
          </ul>
        </section>
      </div>

      <!-- Side column -->
      <aside class="min-w-0 space-y-6 xl:sticky xl:top-20 xl:max-h-[calc(100dvh-6rem)] xl:self-start xl:overflow-y-auto xl:pb-2">
        <section class="sticker-card-trip p-4">
          <div class="flex items-center justify-between">
            <h2 class="tracked-label flex items-center gap-1.5"><PhBed class="size-3.5" /> Stays</h2>
            <button class="icon-btn size-8" aria-label="Add a stay" @click="stayDialog = { open: true }"><PhPlus class="size-4" /></button>
          </div>
          <p v-if="!sortedStays.length" class="mt-2 text-sm text-zinc-500">Where are you staying?</p>
          <ul class="mt-2 space-y-1">
            <li v-for="stay in sortedStays" :key="stay.id">
              <button class="w-full rounded-lg px-2 py-1.5 text-left transition hover:bg-trip-50" @click="stayDialog = { open: true, stay }">
                <span class="block truncate font-medium">{{ stay.name }}</span>
                <span class="block text-xs text-zinc-500">
                  {{ stayTypeNames[stay.type] }} · {{ formatShort(stay.startDate) }} – {{ formatShort(stay.endDate) }}
                  <template v-if="stay.totalCost"> · {{ formatMoney(stay.totalCost, trip.currency) }}</template>
                </span>
              </button>
            </li>
          </ul>
        </section>

        <section class="sticker-card-trip p-4">
          <div class="flex items-center justify-between">
            <h2 class="tracked-label">Transport</h2>
            <button class="icon-btn size-8" aria-label="Add transport" @click="transportDialog = { open: true }"><PhPlus class="size-4" /></button>
          </div>
          <p v-if="!sortedTransport.length" class="mt-2 text-sm text-zinc-500">Flights, buses, ferries and rides.</p>
          <ul class="mt-2 space-y-1">
            <li v-for="segment in sortedTransport" :key="segment.id">
              <button class="flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-left transition hover:bg-trip-50" @click="transportDialog = { open: true, segment }">
                <component :is="transportIcons[segment.mode]" class="size-4 shrink-0 text-trip-500" />
                <span class="min-w-0">
                  <span class="block truncate text-sm font-medium">{{ segment.departureLocation }} → {{ segment.arrivalLocation }}</span>
                  <span class="block text-xs text-zinc-500">{{ formatShort(segment.departureDate) }}, {{ formatHHmm(segment.departureTime) }}</span>
                </span>
              </button>
            </li>
          </ul>
        </section>

        <section class="sticker-card-trip p-4">
          <h2 class="tracked-label flex items-center gap-1.5"><PhUsers class="size-3.5" /> People</h2>
          <ul class="mt-2 space-y-1.5">
            <li v-for="member in sortedMembers" :key="member.uid" class="flex items-center gap-2 text-sm">
              <img v-if="profiles[member.uid]?.photoURL" :src="profiles[member.uid]?.photoURL ?? ''" alt="" class="size-7 rounded-full object-cover" referrerpolicy="no-referrer" />
              <span v-else class="flex size-7 items-center justify-center rounded-full bg-trip-100 text-xs font-bold">{{ memberName(member.uid).charAt(0) }}</span>
              <span class="truncate font-medium">{{ memberName(member.uid) }}</span>
              <span v-if="member.role === 'owner'" class="ml-auto text-[11px] font-semibold tracking-wider text-zinc-500 uppercase">Owner</span>
            </li>
          </ul>
          <div v-if="trip.joinCode" class="mt-4 rounded-xl bg-trip-50 p-3">
            <p class="text-xs text-zinc-600">Invite people with this code</p>
            <div class="mt-1 flex items-center justify-between">
              <span class="font-mono text-xl font-bold tracking-[0.2em]">{{ trip.joinCode }}</span>
              <button class="icon-btn size-8" :aria-label="copied ? 'Copied' : 'Copy code'" @click="copyCode">
                <PhCheck v-if="copied" class="size-4 text-mint-text" /><PhCopy v-else class="size-4" />
              </button>
            </div>
          </div>
          <div v-if="isFreeTrip && members.length >= freeMemberLimit" class="mt-3">
            <UnlockNote v-if="isOwner" :reason="`Free trips hold up to ${freeMemberLimit} people. Unlock for bigger groups.`" />
            <p v-else class="text-xs text-zinc-500">This trip is full. The owner can unlock Agdayo for bigger groups.</p>
          </div>
        </section>
      </aside>
    </div>

    <TripFormDialog v-model:open="editingTrip" :trip="trip" />
    <ActivityDialog v-model:open="activityDialog.open" :trip="trip" :activity="activityDialog.activity" :day="activityDialog.day" />
    <StayDialog v-model:open="stayDialog.open" :trip="trip" :stay="stayDialog.stay" />
    <TransportDialog v-model:open="transportDialog.open" :trip="trip" :segment="transportDialog.segment" :day="transportDialog.day" />
    <DayNoteDialog v-model:open="noteDialog.open" :trip="trip" :note="noteDialog.note" :day="noteDialog.day" />
  </main>
</template>
