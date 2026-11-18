<script setup lang="ts">
import { computed, ref, toRef, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useIntervalFn } from '@vueuse/core'
import {
  DropdownMenuContent, DropdownMenuItem, DropdownMenuPortal, DropdownMenuRoot, DropdownMenuTrigger,
} from 'reka-ui'
import {
  PhArrowRight, PhBed, PhCaretLeft, PhDotsThree, PhMapTrifold, PhNavigationArrow, PhNote, PhPencilSimple, PhPlus, PhSparkle,
} from '@phosphor-icons/vue'
import ActivityDialog from '@/components/ActivityDialog.vue'
import DayNoteDialog from '@/components/DayNoteDialog.vue'
import StayDialog from '@/components/StayDialog.vue'
import TransportDialog from '@/components/TransportDialog.vue'
import TripFormDialog from '@/components/TripFormDialog.vue'
import ConnectClaude from '@/components/ConnectClaude.vue'
import TripBalances from '@/components/sections/TripBalances.vue'
import TripBudget from '@/components/sections/TripBudget.vue'
import TripIdeas from '@/components/sections/TripIdeas.vue'
import TripMap from '@/components/sections/TripMap.vue'
import TripMembers from '@/components/sections/TripMembers.vue'
import TripPolls from '@/components/sections/TripPolls.vue'
import TripPrep from '@/components/sections/TripPrep.vue'
import { provideTripContext } from '@/composables/tripContext'
import { useTripContent } from '@/composables/useTripContent'
import type { Activity, DayNote, Stay, Transport } from '@/lib/model'
import { stayTypeNames, transportModeNames } from '@/lib/model'
import {
  combine, formatDay, formatHHmm, formatMoney, formatRange, formatShort, formatTime, isSameDay, startOfDay, tripDays, tripStatus,
} from '@/lib/dates'
import { iconFor, transportIcons } from '@/lib/icons'
import { balances, spentBreakdown } from '@/lib/money'
import { useTripsStore } from '@/stores/trips'

const props = defineProps<{ id: string }>()

const tripsStore = useTripsStore()
const trip = computed(() => tripsStore.trip(props.id))
const content = useTripContent(toRef(props, 'id'))
const { activities, stays, transport, dayNotes, members, profiles } = content
const { people, uid, isOwner } = provideTripContext(trip, content)

const route = useRoute()
const router = useRouter()
const now = ref(new Date())
useIntervalFn(() => (now.value = new Date()), 60_000)

/**
 * The trip's sections, named like the iPhone app's section cards. The map isn't a
 * section: like the app's "View on Map", it opens as its own full view.
 */
type Tab = 'itinerary' | 'map' | 'budget' | 'balances' | 'prep' | 'polls' | 'ideas' | 'members' | 'claude'
const costs = computed(() => ({ activities: activities.value, stays: stays.value, transport: transport.value, expenses: content.expenses.value }))
const spentTotal = computed(() => (trip.value ? spentBreakdown(costs.value, trip.value.currency).total : 0))
const tabs = computed(() => {
  const list: { id: Tab; label: string; badge?: string }[] = [
    { id: 'itinerary', label: 'Itinerary' },
    { id: 'budget', label: 'Budget', badge: trip.value ? formatMoney(spentTotal.value, trip.value.currency) : undefined },
  ]
  if (members.value.length > 1) list.push({ id: 'balances', label: 'Balances' })
  const done = content.prepTasks.value.filter((t) => t.completed).length
  list.push({ id: 'prep', label: 'Preparation', badge: content.prepTasks.value.length ? `${done}/${content.prepTasks.value.length}` : undefined })
  const openPolls = content.polls.value.filter((p) => !p.isClosed).length
  list.push({ id: 'polls', label: 'Polls', badge: openPolls ? `${openPolls} Open` : undefined })
  list.push({ id: 'ideas', label: 'Ideas', badge: content.ideas.value.length ? String(content.ideas.value.length) : undefined })
  list.push({ id: 'members', label: 'Members', badge: String(members.value.length || 1) })
  return list
})
const validTabs: Tab[] = ['itinerary', 'map', 'budget', 'balances', 'prep', 'polls', 'ideas', 'members', 'claude']
const tab = computed<Tab>(() => {
  const wanted = route.query.tab as Tab
  if (wanted === 'balances' && members.value.length <= 1) return 'itinerary'
  return validTabs.includes(wanted) ? wanted : 'itinerary'
})
function selectTab(id: Tab) {
  void router.replace({ query: id === 'itinerary' ? {} : { tab: id } })
}

const status = computed(() => (trip.value ? tripStatus(trip.value.startDate, trip.value.endDate, now.value) : null))
const days = computed(() => (trip.value ? tripDays(trip.value.startDate, trip.value.endDate) : []))
const todayIndex = computed(() => days.value.findIndex((day) => isSameDay(day, now.value)))

// The map view keeps its day in the address, so "View on Map" can open on a day.
const mapDay = computed<number | null>({
  get: () => {
    const value = Number(route.query.day)
    return route.query.day !== undefined && Number.isInteger(value) && value >= 0 && value < days.value.length ? value : null
  },
  set: (value) => void router.replace({ query: { tab: 'map', ...(value === null ? {} : { day: String(value) }) } }),
})
function openMap(day: number | null = todayIndex.value >= 0 ? todayIndex.value : null) {
  void router.push({ query: { tab: 'map', ...(day === null ? {} : { day: String(day) }) } })
}

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

function entryTitle(entry: Entry): string {
  if (entry.kind === 'activity') return entry.activity.title
  if ('segment' in entry) return `${entry.segment.departureLocation} → ${entry.segment.arrivalLocation}`
  return entry.stay.name
}
function entryPlace(entry: Entry): string {
  if (entry.kind === 'activity') return entry.activity.location
  if ('segment' in entry) return entry.kind === 'depart' ? entry.segment.departureLocation : entry.segment.arrivalLocation
  return entry.stay.location
}
function entryKind(entry: Entry): string | null {
  if ('segment' in entry) return `${transportModeNames[entry.segment.mode]} · ${entry.kind === 'depart' ? 'Departure' : 'Arrival'}`
  if (entry.kind === 'check-in') return 'Check-in'
  if (entry.kind === 'check-out') return 'Check-out'
  return null
}
function entryIcon(entry: Entry) {
  if (entry.kind === 'activity') return iconFor(entry.activity.iconName)
  if ('segment' in entry) return transportIcons[entry.segment.mode]
  return PhBed
}
/** Apple Maps directions to where the entry happens. */
function directionsUrl(entry: Entry): string | null {
  let lat: number | null = null
  let lng: number | null = null
  if (entry.kind === 'activity') [lat, lng] = [entry.activity.latitude, entry.activity.longitude]
  else if ('stay' in entry) [lat, lng] = [entry.stay.latitude, entry.stay.longitude]
  else if (entry.kind === 'depart') [lat, lng] = [entry.segment.departureLatitude, entry.segment.departureLongitude]
  else [lat, lng] = [entry.segment.arrivalLatitude, entry.segment.arrivalLongitude]
  if (lat !== null && lng !== null) return `https://maps.apple.com/?daddr=${lat},${lng}`
  const place = entryPlace(entry)
  return place ? `https://maps.apple.com/?daddr=${encodeURIComponent([place, trip.value?.location].filter(Boolean).join(', '))}` : null
}

/** Next Up: the next thing on the plan, while the trip is coming up or underway. */
const nextUp = computed(() => (status.value?.kind === 'past' ? undefined : entries.value.find((entry) => entry.time >= now.value)))
const nextUpWhen = computed(() => {
  const entry = nextUp.value
  if (!entry) return ''
  const minutes = Math.round((entry.time.getTime() - now.value.getTime()) / 60_000)
  if (minutes < 60) return `in ${Math.max(minutes, 1)} min`
  if (isSameDay(entry.time, now.value) && minutes < 12 * 60) {
    const h = Math.floor(minutes / 60)
    const m = minutes % 60
    return `in ${h} h${m ? ` ${m} min` : ''}`
  }
  return formatDay(entry.time)
})
const nextUpDay = computed(() => (nextUp.value ? days.value.findIndex((day) => isSameDay(day, nextUp.value!.time)) : -1))
/** On the day happening now, what's already behind you is dimmed. */
const isPast = (entry: Entry) => status.value?.kind === 'active' && entry.time < now.value

/** Planning, like the app's header bar: which of the five parts of a plan have something in them. */
const planning = computed(() => {
  const parts = [activities.value.length, content.budgetCategories.value.length, stays.value.length, content.prepTasks.value.length, transport.value.length]
  return { done: parts.filter((n) => n > 0).length, total: parts.length }
})
const monthDay = (value: Date) => formatShort(value).toUpperCase()

const sortedStays = computed(() => [...stays.value].sort((a, b) => a.startDate.getTime() - b.startDate.getTime()))
const sortedTransport = computed(() =>
  [...transport.value].sort((a, b) => combine(a.departureDate, a.departureTime).getTime() - combine(b.departureDate, b.departureTime).getTime()),
)
const budgetFraction = computed(() => (trip.value && trip.value.overallBudget > 0 ? Math.min(spentTotal.value / trip.value.overallBudget, 1) : 0))
/** The signed-in person's balance: positive means they get money back. */
const myBalance = computed(() => {
  if (!trip.value || members.value.length < 2) return null
  const net = balances(costs.value, content.settlements.value, trip.value.currency, new Set(members.value.map((m) => m.uid)))
  return net[uid.value] ?? 0
})

// The map view's list: the chosen day's stops, activities numbered like their pins.
/** The stop picked in the map view's list or on the map, as its pin's key. */
const mapFocus = ref<string | null>(null)
function pinKey(entry: Entry): string {
  if (entry.kind === 'activity') return `a-${entry.activity.id}`
  if ('stay' in entry) return `s-${entry.stay.id}`
  return `${entry.kind === 'depart' ? 'tf' : 'tt'}-${entry.segment.id}`
}
watch(mapDay, () => (mapFocus.value = null))
function focusEntry(entry: Entry) {
  // Picking the same stop again still zooms back to it.
  mapFocus.value = null
  void Promise.resolve().then(() => (mapFocus.value = pinKey(entry)))
}
const mapEntries = computed(() => {
  const day = mapDay.value === null ? null : days.value[mapDay.value]
  let number = 0
  return entries.value
    .filter((entry) => !day || isSameDay(entry.time, day))
    .map((entry) => ({ entry, number: entry.kind === 'activity' ? ++number : null }))
})

/** A pin tapped on the map picks its stop in the list. */
function onPinSelect(key: string | null) {
  mapFocus.value = key
  if (key) document.getElementById(`stop-${key}`)?.scrollIntoView({ behavior: 'smooth', block: 'nearest' })
}

function scrollToDay(index: number) {
  document.getElementById(`day-${index}`)?.scrollIntoView({ behavior: 'smooth', block: 'start' })
}

// Dialogs
const editingTrip = ref(false)
const activityDialog = ref<{ open: boolean; activity?: Activity; day?: Date }>({ open: false })
const stayDialog = ref<{ open: boolean; stay?: Stay }>({ open: false })
const transportDialog = ref<{ open: boolean; segment?: Transport; day?: Date }>({ open: false })
const noteDialog = ref<{ open: boolean; note?: DayNote; day: Date }>({ open: false, day: new Date() })

function openEntry(entry: Entry) {
  if (entry.kind === 'activity') activityDialog.value = { open: true, activity: entry.activity }
  else if ('segment' in entry) transportDialog.value = { open: true, segment: entry.segment }
  else stayDialog.value = { open: true, stay: entry.stay }
}
const openActivity = (a: Activity) => (activityDialog.value = { open: true, activity: a })
const openStay = (s: Stay) => (stayDialog.value = { open: true, stay: s })
const openTransport = (t: Transport) => (transportDialog.value = { open: true, segment: t })

// Phones: four sections in the bottom bar, the rest under More.
const phoneTabs: { id: Tab; label: string }[] = [
  { id: 'itinerary', label: 'Itinerary' },
  { id: 'budget', label: 'Budget' },
  { id: 'prep', label: 'Preparation' },
  { id: 'ideas', label: 'Ideas' },
]
const moreTabs = computed(() => tabs.value.filter((t) => !phoneTabs.some((p) => p.id === t.id)))
const inMore = computed(() => !phoneTabs.some((p) => p.id === tab.value))
const today = computed(() => startOfDay(now.value))
</script>

<template>
  <main v-if="!trip && tripsStore.loading" class="mx-auto max-w-5xl px-4 py-10">
    <div class="h-48 animate-pulse rounded-card bg-card-surface" />
  </main>

  <main v-else-if="!trip" class="mx-auto max-w-md px-4 py-20 text-center">
    <h1 class="display-title text-5xl">Trip not found</h1>
    <p class="mt-3 text-zinc-600">It may have been deleted, or you’re no longer a member.</p>
    <RouterLink to="/" class="btn-primary mt-6">Back to My Trips</RouterLink>
  </main>

  <!-- ───────── Map view: the plan beside a big map ───────── -->
  <main v-else-if="tab === 'map'" :data-theme="trip.theme" class="fade-in flex flex-col lg:h-full">
    <header class="flex flex-wrap items-center gap-x-6 gap-y-3 border-b border-trip-200 bg-trip-50 px-4 py-3 lg:px-6">
      <button class="btn-secondary h-11 pr-3 pl-2 text-trip-700" @click="selectTab('itinerary')"><PhCaretLeft class="size-4" /> Back to trip</button>
      <div class="flex min-w-0 flex-wrap items-baseline gap-x-3 gap-y-1">
        <h1 class="font-display text-4xl leading-none font-normal text-trip-700 uppercase sm:text-5xl">{{ trip.location || trip.name }}</h1>
        <span v-if="trip.location" class="font-display text-lg font-semibold tracking-[0.05em] text-trip-700 uppercase">{{ trip.name }}</span>
        <span
          v-if="status"
          class="rounded-pill px-2 py-0.5 text-[11px] font-bold tracking-wider uppercase"
          :class="status.kind === 'active' ? 'bg-mint text-mint-text' : status.kind === 'past' ? 'bg-zinc-100 text-zinc-600' : 'bg-trip-100 text-ink/75'"
        >{{ status.label }}</span>
      </div>
      <nav class="hidden flex-wrap gap-1 rounded-[14px] border border-trip-200 bg-white p-1 xl:flex" aria-label="Trip sections">
        <button
          v-for="t in tabs"
          :key="t.id"
          class="rounded-[10px] px-3 py-2 text-sm font-semibold transition hover:bg-trip-50"
          @click="selectTab(t.id)"
        >{{ t.label }}</button>
      </nav>
      <button class="btn-primary ml-auto h-10 bg-maroon hover:bg-maroon/90" @click="selectTab('claude')">
        <PhSparkle class="size-4" /> Claude <span class="font-medium opacity-80">· Plan with AI</span>
      </button>
    </header>

    <div class="flex min-h-0 flex-1 flex-col-reverse lg:flex-row">
      <!-- The day's stops -->
      <section aria-label="Itinerary" class="space-y-4 px-4 py-5 lg:w-[440px] lg:shrink-0 lg:overflow-y-auto lg:border-r lg:border-black/5 lg:px-6">
        <div class="grid grid-cols-4 gap-1.5">
          <button
            class="h-13 rounded-xl border text-sm font-semibold transition"
            :class="mapDay === null ? 'border-trip-700 bg-trip-700 text-white' : 'border-black/10 bg-white hover:bg-trip-50'"
            @click="mapDay = null"
          >All days</button>
          <button
            v-for="(d, i) in days"
            :key="d.getTime()"
            class="flex h-13 flex-col items-center justify-center rounded-xl border text-sm transition"
            :class="mapDay === i ? 'border-trip-700 bg-trip-700 text-white' : 'border-black/10 bg-white hover:bg-trip-50'"
            @click="mapDay = i"
          >
            <b>Day {{ i + 1 }}</b>
            <span class="text-xs" :class="mapDay === i ? 'text-white/85' : 'text-zinc-500'">{{ i === todayIndex ? 'Today' : formatShort(d) }}</span>
          </button>
        </div>

        <div class="flex items-baseline justify-between gap-2">
          <h2 class="font-display text-3xl font-semibold uppercase">{{ mapDay === null ? 'All days' : formatDay(days[mapDay]!) }}</h2>
          <span class="text-sm text-zinc-500">{{ mapEntries.filter((e) => e.number).length }} Activities</span>
        </div>

        <p v-if="!mapEntries.length" class="rounded-dense border border-dashed border-trip-200 p-4 text-sm text-zinc-500">Nothing planned yet.</p>
        <ol class="relative">
          <li v-for="({ entry, number }, i) in mapEntries" :key="entry.key" :id="`stop-${pinKey(entry)}`" class="rise flex gap-3" :style="{ '--i': i }">
            <span class="flex flex-col items-center">
              <span
                v-if="number"
                class="flex size-7 shrink-0 items-center justify-center rounded-full border-2 text-xs font-bold"
                :class="mapFocus === pinKey(entry) ? 'border-trip-700 bg-trip-700 text-white' : 'border-trip-700 bg-white text-trip-700'"
              >{{ number }}</span>
              <span v-else class="flex size-7 shrink-0 items-center justify-center rounded-full bg-card-surface text-zinc-600">
                <component :is="entryIcon(entry)" class="size-3.5" />
              </span>
              <span v-if="i < mapEntries.length - 1" class="w-0.5 flex-1 bg-trip-200" />
            </span>
            <div
              class="mb-3 min-w-0 flex-1 pb-1"
              :style="isPast(entry) ? 'opacity: 0.6' : ''"
            >
              <p class="text-xs font-semibold" :class="mapFocus === pinKey(entry) || nextUp?.key === entry.key ? 'text-trip-700' : 'text-zinc-500'">
                {{ mapDay === null ? `${formatShort(entry.time)}, ` : '' }}{{ formatTime(entry.time) }}<template v-if="entryKind(entry)"> · {{ entryKind(entry) }}</template>
                <template v-if="nextUp?.key === entry.key"> · Next Up</template>
              </p>
              <div class="flex items-start gap-2">
                <button class="mt-0.5 min-w-0 flex-1 text-left" :aria-label="`Show ${entryTitle(entry)} on the map`" @click="focusEntry(entry)">
                  <span class="block font-semibold hover:underline">{{ entryTitle(entry) }}</span>
                  <span v-if="entryPlace(entry) && entry.kind === 'activity'" class="block truncate text-sm text-zinc-500">{{ entryPlace(entry) }}</span>
                </button>
                <a
                  v-if="directionsUrl(entry)"
                  :href="directionsUrl(entry)!"
                  target="_blank"
                  rel="noopener"
                  class="icon-btn -mt-1 shrink-0"
                  :aria-label="`Directions to ${entryTitle(entry)}`"
                  title="Directions"
                ><PhNavigationArrow class="size-4" /></a>
                <button class="icon-btn -mt-1 -mr-1 shrink-0" :aria-label="`Edit ${entryTitle(entry)}`" title="Edit" @click="openEntry(entry)"><PhPencilSimple class="size-4" /></button>
              </div>
            </div>
          </li>
        </ol>
        <button
          class="h-12 w-full rounded-[14px] border border-dashed border-trip-500 text-sm font-semibold text-trip-700 transition hover:bg-trip-50"
          @click="activityDialog = { open: true, day: mapDay === null ? undefined : days[mapDay] }"
        >+ Add Activity</button>
      </section>

      <!-- Map -->
      <section aria-label="Map" class="relative h-[55dvh] min-w-0 lg:h-auto lg:flex-1">
        <TripMap v-model:day="mapDay" variant="fill" :focus="mapFocus" @select="onPinSelect" />
      </section>
    </div>

    <ActivityDialog v-model:open="activityDialog.open" :trip="trip" :activity="activityDialog.activity" :day="activityDialog.day" />
    <StayDialog v-model:open="stayDialog.open" :trip="trip" :stay="stayDialog.stay" />
    <TransportDialog v-model:open="transportDialog.open" :trip="trip" :segment="transportDialog.segment" :day="transportDialog.day" />
  </main>

  <!-- ───────── Trip page ───────── -->
  <main v-else :data-theme="trip.theme" class="overflow-x-clip px-4 pt-4 pb-28 lg:px-8 lg:pt-6 lg:pb-16 xl:px-10">
    <RouterLink to="/" class="btn-ghost -ml-3 mb-2 lg:hidden"><PhCaretLeft class="size-4" /> My Trips</RouterLink>

    <!-- Header: the trip beside Next Up -->
    <div :key="trip.id" class="flex flex-wrap items-stretch gap-5 xl:gap-6">
      <section class="rise flex min-w-0 flex-[3_1_520px] flex-col gap-2 rounded-card border border-trip-200 bg-trip-50 px-5 pt-5 pb-6 shadow-[2px_2px_0_0_var(--trip-200)] sm:px-8 sm:pt-7 xl:px-9 xl:pt-8">
        <div class="flex items-center gap-3">
          <span
            v-if="status"
            class="rounded-pill px-2 py-1 text-[11px] font-bold tracking-wider uppercase"
            :class="status.kind === 'active' ? 'bg-mint text-mint-text' : status.kind === 'past' ? 'bg-zinc-100 text-zinc-600' : 'bg-trip-100 text-ink/75'"
          >{{ status.label }}</span>
          <span class="text-sm text-zinc-600">{{ formatRange(trip.startDate, trip.endDate) }}</span>
          <button v-if="isOwner" class="icon-btn -my-2 ml-auto" aria-label="Trip Settings" @click="editingTrip = true">
            <PhPencilSimple class="size-4.5" />
          </button>
        </div>
        <!-- Same type as iOS TripHeaderView: destination in Barlow Condensed Regular, trip name in SemiBold with tracking -->
        <h1 class="mt-1 font-display text-4xl leading-[0.95] font-normal break-words text-trip-700 uppercase sm:text-5xl">{{ trip.location || trip.name }}</h1>
        <p v-if="trip.location" class="font-display text-xl font-semibold tracking-[0.05em] break-words text-trip-700 uppercase">{{ trip.name }}</p>
        <p v-if="trip.tripDescription" class="mt-1 max-w-2xl text-[15px] leading-relaxed whitespace-pre-line text-zinc-700">{{ trip.tripDescription }}</p>

        <div class="mt-3 flex flex-wrap items-end gap-x-7 gap-y-4">
          <dl class="flex gap-7">
            <div>
              <dt class="tracked-label text-zinc-600">Depart</dt>
              <dd class="font-display text-3xl leading-tight font-semibold text-trip-700">{{ monthDay(trip.startDate) }}</dd>
            </div>
            <div>
              <dt class="tracked-label text-zinc-600">Return</dt>
              <dd class="font-display text-3xl leading-tight font-semibold text-trip-700">{{ monthDay(trip.endDate) }}</dd>
            </div>
            <div>
              <dt class="tracked-label text-zinc-600">Days</dt>
              <dd class="font-display text-3xl leading-tight font-semibold text-trip-700">{{ days.length }}</dd>
            </div>
          </dl>
          <div class="min-w-40 flex-1 pb-1.5 sm:max-w-56">
            <div class="flex justify-between">
              <span class="tracked-label text-zinc-600">Planning</span>
              <span class="tracked-label text-zinc-600">{{ planning.done }} of {{ planning.total }} done</span>
            </div>
            <div class="mt-1.5 h-1.5 overflow-hidden rounded-full bg-trip-200">
              <div class="grow-x h-full rounded-full bg-trip-500 transition-[width] duration-500" :style="{ width: `${(planning.done / planning.total) * 100}%` }" />
            </div>
          </div>
          <div class="ml-auto flex items-center gap-2">
            <span class="flex">
              <template v-for="(person, i) in people.slice(0, 4)" :key="person.uid">
                <img
                  v-if="profiles[person.uid]?.photoURL"
                  :src="profiles[person.uid]?.photoURL ?? ''"
                  :alt="person.name"
                  class="size-8 rounded-full border-2 border-trip-50 object-cover"
                  :class="i ? '-ml-2' : ''"
                  referrerpolicy="no-referrer"
                />
                <span
                  v-else
                  class="flex size-8 items-center justify-center rounded-full border-2 border-trip-50 bg-ink text-xs font-bold text-white"
                  :class="i ? '-ml-2' : ''"
                  :title="person.name"
                >{{ person.name.charAt(0) }}</span>
              </template>
            </span>
            <button class="h-9 rounded-[10px] border border-dashed border-trip-700 px-3 text-[13px] font-semibold text-trip-700 transition hover:bg-trip-100" @click="selectTab('members')">Invite</button>
          </div>
        </div>
      </section>

      <!-- Next Up -->
      <aside v-if="nextUp" class="rise flex flex-[1_1_300px] flex-col gap-3 rounded-card bg-ink p-6 text-white">
        <p class="flex items-center gap-2 text-[11px] font-bold tracking-[0.11em] text-trip-200 uppercase"><span class="live-dot" aria-hidden="true" /> Next Up · {{ nextUpWhen }}</p>
        <p class="font-display text-5xl leading-none font-light xl:text-6xl">{{ formatTime(nextUp.time) }}</p>
        <div class="min-w-0">
          <p v-if="entryKind(nextUp)" class="text-xs font-bold tracking-wider text-zinc-400 uppercase">{{ entryKind(nextUp) }}</p>
          <p class="text-xl font-semibold break-words">{{ entryTitle(nextUp) }}</p>
          <p v-if="entryPlace(nextUp) && nextUp.kind === 'activity'" class="mt-1 truncate text-sm text-zinc-300">{{ entryPlace(nextUp) }}</p>
        </div>
        <div class="mt-auto flex gap-2 pt-2">
          <a
            v-if="directionsUrl(nextUp)"
            :href="directionsUrl(nextUp)!"
            target="_blank"
            rel="noopener"
            class="flex h-11 flex-1 items-center justify-center gap-1.5 rounded-xl bg-white text-sm font-semibold text-ink transition hover:bg-zinc-100"
          ><PhNavigationArrow class="size-4" /> Directions</a>
          <button
            class="flex h-11 flex-1 items-center justify-center gap-1.5 rounded-xl border border-zinc-600 text-sm font-semibold transition hover:bg-white/10"
            @click="openMap(nextUpDay >= 0 ? nextUpDay : null)"
          ><PhMapTrifold class="size-4" /> View on Map</button>
        </div>
      </aside>
    </div>

    <!-- Sections (desktop) -->
    <nav class="mt-6 hidden flex-wrap items-center gap-1 border-b border-black/10 lg:flex" aria-label="Trip sections">
      <button
        v-for="t in tabs"
        :key="t.id"
        class="press -mb-px flex items-center gap-2 border-b-[3px] px-3.5 py-3 text-[15px] transition"
        :class="tab === t.id ? 'border-trip-700 font-bold text-trip-700' : 'border-transparent font-semibold text-zinc-600 hover:text-ink'"
        :aria-current="tab === t.id ? 'page' : undefined"
        @click="selectTab(t.id)"
      >
        {{ t.label }}
        <span v-if="t.badge" class="rounded-pill px-1.5 py-0.5 text-xs font-semibold" :class="t.id === 'polls' ? 'bg-blush text-maroon' : 'bg-card-surface text-zinc-700'">{{ t.badge }}</span>
      </button>
      <button
        class="mb-2 ml-auto flex h-10 items-center gap-2 rounded-xl px-3.5 text-sm font-semibold text-white transition"
        :class="tab === 'claude' ? 'bg-ink' : 'bg-maroon hover:bg-maroon/90'"
        @click="selectTab('claude')"
      >
        <PhSparkle class="size-4" /> Claude <span class="font-medium opacity-80">· Plan with AI</span>
      </button>
    </nav>

    <p v-if="content.error.value" class="mt-4 rounded-dense bg-danger/10 p-3 text-sm text-danger">{{ content.error.value }}</p>

    <Transition name="tab" mode="out-in">
    <div v-if="tab !== 'itinerary'" :key="tab" class="mt-6">
      <TripBudget v-if="tab === 'budget'" @activity="openActivity" @stay="openStay" @transport="openTransport" />
      <TripBalances v-else-if="tab === 'balances'" />
      <TripPrep v-else-if="tab === 'prep'" />
      <TripPolls v-else-if="tab === 'polls'" />
      <TripIdeas v-else-if="tab === 'ideas'" />
      <TripMembers v-else-if="tab === 'members'" />
      <ConnectClaude v-else-if="tab === 'claude'" />
    </div>

    <div v-else key="itinerary">
      <!-- Day jump bar: stays in view while scrolling -->
      <nav class="sticky top-14 z-20 -mx-4 mt-4 flex gap-2 overflow-x-auto bg-canvas/90 px-4 py-2.5 backdrop-blur lg:top-0 lg:-mx-8 lg:px-8 xl:-mx-10 xl:px-10" aria-label="Days">
        <button
          v-for="(day, index) in days"
          :key="day.getTime()"
          class="h-10 shrink-0 rounded-full border px-3.5 text-sm font-semibold transition"
          :class="index === todayIndex ? 'border-trip-700 bg-trip-700 text-white' : 'border-trip-border bg-white text-ink hover:bg-trip-50'"
          @click="scrollToDay(index)"
        >
          {{ formatDay(day).replace(/,.*$/, '') }} {{ day.getDate() }}<template v-if="index === todayIndex"> · Today</template>
        </button>
      </nav>

      <div class="mt-4 flex flex-wrap items-start gap-8">
        <!-- Itinerary -->
        <div class="grid min-w-0 flex-[999_1_520px] content-start gap-10">
          <section v-for="(day, index) in days" :id="`day-${index}`" :key="day.getTime()" class="min-w-0 scroll-mt-32 lg:scroll-mt-20">
            <div class="mb-3 flex items-end justify-between gap-2">
              <div>
                <p class="tracked-label" :class="index === todayIndex ? 'text-trip-700' : ''">Day {{ index + 1 }}<template v-if="index === todayIndex"> · Today</template></p>
                <h2 class="font-display text-4xl leading-none font-semibold uppercase">{{ formatDay(day) }}</h2>
              </div>
              <DropdownMenuRoot>
                <DropdownMenuTrigger class="btn-secondary h-11 px-3.5" :aria-label="`Add to day ${index + 1}`"><PhPlus class="size-4" /> Add</DropdownMenuTrigger>
                <DropdownMenuPortal>
                  <DropdownMenuContent align="end" :side-offset="6" class="menu-content z-50 min-w-52 rounded-dense border border-secondary bg-white p-1 shadow-sticker">
                    <DropdownMenuItem class="menu-item" @select="activityDialog = { open: true, day }">Add Activity</DropdownMenuItem>
                    <DropdownMenuItem class="menu-item" @select="transportDialog = { open: true, day }">Add Transport</DropdownMenuItem>
                    <DropdownMenuItem class="menu-item" @select="stayDialog = { open: true }">Add Accommodation</DropdownMenuItem>
                    <DropdownMenuItem class="menu-item" @select="noteDialog = { open: true, day }">Add Note</DropdownMenuItem>
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
              <PhNote class="mt-0.5 size-4 shrink-0 text-amber-700" />
              <span class="min-w-0">
                <span v-if="note.title" class="block font-semibold">{{ note.title }}</span>
                <span v-if="note.content" class="block text-sm whitespace-pre-line text-zinc-700">{{ note.content }}</span>
              </span>
            </button>

            <ol v-if="entriesOn(day).length" class="relative space-y-2.5 before:absolute before:top-4 before:bottom-4 before:left-[calc(5.5rem+1px)] before:w-px before:bg-trip-200">
              <li v-for="(entry, n) in entriesOn(day)" :key="entry.key" class="rise" :style="{ '--i': n + 1 }">
                <button class="group flex w-full items-start gap-3.5 text-left" :class="isPast(entry) ? 'opacity-60' : ''" @click="openEntry(entry)">
                  <span
                    class="w-16 shrink-0 pt-4 text-right text-[13px] tabular-nums"
                    :class="nextUp?.key === entry.key ? 'font-bold text-trip-700' : 'font-semibold text-zinc-600'"
                  >{{ formatTime(entry.time) }}</span>
                  <span
                    class="relative z-10 mt-2.5 flex size-8 shrink-0 items-center justify-center rounded-full border-2 border-canvas"
                    :class="nextUp?.key === entry.key ? 'bg-trip-700 text-white' : 'bg-trip-100 text-trip-700'"
                  >
                    <component :is="entryIcon(entry)" class="size-4" />
                  </span>
                  <span
                    class="min-w-0 flex-1 rounded-dense bg-white px-4.5 py-3.5 transition duration-200 ease-(--ease-spring) group-hover:-translate-y-0.5 group-active:scale-[0.99]"
                    :class="nextUp?.key === entry.key ? 'border-2 border-trip-700 shadow-[2px_2px_0_0_var(--trip-700)]' : 'border border-secondary shadow-sticker'"
                  >
                    <span v-if="entryKind(entry) || nextUp?.key === entry.key" class="flex flex-wrap gap-x-2 text-[11px] font-bold tracking-[0.11em] uppercase">
                      <span v-if="entryKind(entry)" class="text-zinc-600">{{ entryKind(entry) }}</span>
                      <span v-if="nextUp?.key === entry.key" class="text-trip-700">Next Up</span>
                    </span>
                    <template v-if="entry.kind === 'activity'">
                      <span class="block text-base font-semibold">{{ entry.activity.title }}</span>
                      <span v-if="entry.activity.location" class="block truncate text-sm text-zinc-500">{{ entry.activity.location }}</span>
                      <span v-if="entry.activity.activityDescription" class="mt-1.5 line-clamp-2 block text-sm leading-snug text-zinc-700">{{ entry.activity.activityDescription }}</span>
                      <span v-if="entry.activity.cost" class="mt-2.5 inline-block rounded-pill bg-trip-100 px-2 py-0.5 text-xs font-semibold text-ink">
                        {{ formatMoney(entry.activity.cost, entry.activity.costCurrency ?? trip.currency) }}<template v-if="entry.activity.costNote"> · {{ entry.activity.costNote }}</template>
                      </span>
                    </template>
                    <template v-else-if="'segment' in entry">
                      <span class="flex flex-wrap items-center gap-x-1.5 text-base font-semibold">
                        <span>{{ entry.segment.departureLocation }}</span>
                        <PhArrowRight class="size-4 shrink-0 text-trip-700" />
                        <span>{{ entry.segment.arrivalLocation }}</span>
                      </span>
                      <span class="block text-sm text-zinc-500">
                        <template v-if="entry.segment.arrivalTime">Arrives {{ formatHHmm(entry.segment.arrivalTime) }}</template>
                        <template v-if="entry.segment.bookingRef"> · Ref {{ entry.segment.bookingRef }}</template>
                        <template v-if="entry.segment.seatNumber"> · Seat {{ entry.segment.seatNumber }}</template>
                      </span>
                    </template>
                    <template v-else-if="'stay' in entry">
                      <span class="block text-base font-semibold">{{ entry.stay.name }}</span>
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
              Nothing planned yet. Add Activity.
            </button>
          </section>

          <section v-if="outside.length">
            <p class="tracked-label">Outside the trip dates</p>
            <ul class="mt-2 space-y-2">
              <li v-for="entry in outside" :key="entry.key">
                <button class="sticker-card w-full px-4 py-3 text-left" @click="openEntry(entry)">
                  <span class="block font-semibold">{{ entryTitle(entry) }}</span>
                  <span class="text-sm text-zinc-500">{{ formatDay(entry.time) }}, {{ formatTime(entry.time) }}</span>
                </button>
              </li>
            </ul>
          </section>
        </div>

        <!-- Side column -->
        <aside class="rise min-w-0 flex-[1_1_300px] space-y-4 lg:max-w-[380px] xl:sticky xl:top-20 xl:max-h-[calc(100dvh-6rem)] xl:-mr-1.5 xl:overflow-y-auto xl:pr-1.5 xl:pb-2">
          <!-- Map preview: opens the map view -->
          <section class="overflow-hidden rounded-card-sm border border-trip-border bg-white shadow-[2px_2px_0_0_var(--trip-200)]">
            <div class="relative h-48">
              <TripMap :day="todayIndex >= 0 ? todayIndex : null" variant="preview" />
              <button class="absolute inset-0 z-10" aria-label="View on Map" @click="openMap()" />
            </div>
            <div class="flex items-center justify-between px-4.5 py-3.5">
              <span class="text-sm font-semibold">{{ todayIndex >= 0 ? 'Today’s route' : 'All days' }}</span>
              <button class="text-sm font-semibold text-trip-700 hover:underline" @click="openMap()">View on Map</button>
            </div>
          </section>

          <!-- Budget -->
          <section class="sticker-card space-y-2.5 rounded-card-sm p-4.5">
            <div class="flex items-center justify-between">
              <h2 class="tracked-label">Budget · Spent</h2>
              <button class="text-sm font-semibold text-trip-700 hover:underline" @click="selectTab('budget')">Open</button>
            </div>
            <p class="font-display text-[2.75rem] leading-none font-light text-maroon">
              {{ formatMoney(spentTotal, trip.currency) }}
              <span v-if="trip.overallBudget > 0" class="font-sans text-sm font-normal text-zinc-500">of {{ formatMoney(trip.overallBudget, trip.currency) }}</span>
            </p>
            <div v-if="trip.overallBudget > 0" class="h-1.5 overflow-hidden rounded-full bg-rose-track">
              <div class="grow-x h-full rounded-full bg-brand-rose" :style="{ width: `${budgetFraction * 100}%` }" />
            </div>
            <div v-if="myBalance !== null" class="flex items-center justify-between gap-2 pt-1 text-sm">
              <span class="text-zinc-700">
                <template v-if="myBalance > 0.01">You get back <b class="text-mint-text">{{ formatMoney(myBalance, trip.currency) }}</b></template>
                <template v-else-if="myBalance < -0.01">You owe <b class="text-danger">{{ formatMoney(-myBalance, trip.currency) }}</b></template>
                <template v-else>Everyone is square.</template>
              </span>
              <button class="font-semibold text-trip-700 hover:underline" @click="selectTab('balances')">Settle Up</button>
            </div>
          </section>

          <!-- Accommodations -->
          <section class="sticker-card rounded-card-sm p-4.5">
            <div class="flex items-center justify-between">
              <h2 class="tracked-label flex items-center gap-1.5"><PhBed class="size-3.5" /> Accommodations</h2>
              <button class="icon-btn size-8" aria-label="Add Accommodation" @click="stayDialog = { open: true }"><PhPlus class="size-4" /></button>
            </div>
            <p v-if="!sortedStays.length" class="mt-2 text-sm text-zinc-500">No Accommodations Yet</p>
            <ul class="mt-2 space-y-1">
              <li v-for="stay in sortedStays" :key="stay.id">
                <button class="-mx-2 w-[calc(100%+1rem)] rounded-lg px-2 py-1.5 text-left transition hover:bg-trip-50" @click="openStay(stay)">
                  <span class="block truncate font-semibold">{{ stay.name }}</span>
                  <span class="block text-sm text-zinc-500">
                    {{ stayTypeNames[stay.type] }} · {{ formatShort(stay.startDate) }} – {{ formatShort(stay.endDate) }}
                    <template v-if="stay.totalCost"> · {{ formatMoney(stay.totalCost, trip.currency) }}</template>
                  </span>
                  <span v-if="startOfDay(stay.startDate) <= today && startOfDay(stay.endDate) >= today" class="mt-0.5 block text-xs font-semibold text-mint-text">
                    {{ isSameDay(stay.endDate, today) ? `Check-out today, ${formatHHmm(stay.checkOutTime)}` : 'Staying here now' }}
                  </span>
                </button>
              </li>
            </ul>
          </section>

          <!-- Transport -->
          <section class="sticker-card rounded-card-sm p-4.5">
            <div class="flex items-center justify-between">
              <h2 class="tracked-label">Transport</h2>
              <button class="icon-btn size-8" aria-label="Add Transport" @click="transportDialog = { open: true }"><PhPlus class="size-4" /></button>
            </div>
            <p v-if="!sortedTransport.length" class="mt-2 text-sm text-zinc-500">No Transport Yet</p>
            <ul class="mt-2 space-y-1">
              <li v-for="segment in sortedTransport" :key="segment.id">
                <button class="-mx-2 flex w-[calc(100%+1rem)] items-center gap-2.5 rounded-lg px-2 py-1.5 text-left transition hover:bg-trip-50" @click="openTransport(segment)">
                  <component :is="transportIcons[segment.mode]" class="size-4 shrink-0 text-trip-700" />
                  <span class="min-w-0">
                    <span class="block truncate text-sm font-semibold">{{ segment.departureLocation }} → {{ segment.arrivalLocation }}</span>
                    <span class="block text-xs text-zinc-500">{{ formatShort(segment.departureDate) }}, {{ formatHHmm(segment.departureTime) }}</span>
                  </span>
                </button>
              </li>
            </ul>
          </section>
        </aside>
      </div>
    </div>
    </Transition>

    <!-- Sections (phones): bottom bar -->
    <nav
      class="fixed inset-x-3 bottom-4 z-30 grid h-16 grid-cols-5 gap-0.5 rounded-[22px] border border-secondary bg-white/90 p-1.5 shadow-sticker backdrop-blur lg:hidden"
      aria-label="Trip sections"
    >
      <button
        v-for="t in phoneTabs"
        :key="t.id"
        class="press truncate rounded-2xl px-1 text-xs font-semibold transition"
        :class="tab === t.id ? 'bg-trip-700 text-white' : 'text-zinc-700'"
        :aria-current="tab === t.id ? 'page' : undefined"
        @click="selectTab(t.id)"
      >{{ t.label }}</button>
      <DropdownMenuRoot>
        <DropdownMenuTrigger
          class="flex flex-col items-center justify-center rounded-2xl text-xs font-semibold transition"
          :class="inMore ? 'bg-trip-700 text-white' : 'text-zinc-700'"
        ><PhDotsThree class="size-5" weight="bold" /> More</DropdownMenuTrigger>
        <DropdownMenuPortal>
          <DropdownMenuContent side="top" align="end" :side-offset="10" class="menu-content z-50 min-w-52 rounded-dense border border-secondary bg-white p-1 shadow-sticker">
            <DropdownMenuItem class="menu-item" @select="openMap()"><PhMapTrifold class="size-4" /> View on Map</DropdownMenuItem>
            <DropdownMenuItem v-for="t in moreTabs" :key="t.id" class="menu-item" @select="selectTab(t.id)">
              {{ t.label }}<span v-if="t.badge" class="ml-auto text-xs text-zinc-500">{{ t.badge }}</span>
            </DropdownMenuItem>
            <DropdownMenuItem class="menu-item" @select="selectTab('claude')"><PhSparkle class="size-4" /> Claude</DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenuPortal>
      </DropdownMenuRoot>
    </nav>

    <TripFormDialog v-model:open="editingTrip" :trip="trip" />
    <ActivityDialog v-model:open="activityDialog.open" :trip="trip" :activity="activityDialog.activity" :day="activityDialog.day" />
    <StayDialog v-model:open="stayDialog.open" :trip="trip" :stay="stayDialog.stay" />
    <TransportDialog v-model:open="transportDialog.open" :trip="trip" :segment="transportDialog.segment" :day="transportDialog.day" />
    <DayNoteDialog v-model:open="noteDialog.open" :trip="trip" :note="noteDialog.note" :day="noteDialog.day" />
  </main>
</template>
