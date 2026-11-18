<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, shallowRef, watch } from 'vue'
import { PhMapPinLine } from '@phosphor-icons/vue'
import type { Activity, Stay, Transport } from '@/lib/model'
import { combine, formatShort, isSameDay, tripDays } from '@/lib/dates'
import { geocode, loadMapKit, type Coordinate, type MapKit, type MKAnnotation, type MKMap, type MKOverlay } from '@/lib/mapkit'
import { useTripContext } from '@/composables/tripContext'

/**
 * The trip map (TripMapView in the app): activities, stays and both ends of each
 * ride. Pick a day to see just that day, numbered in order, with a line joining
 * its activities (travel legs only ever join two activities, like the itinerary).
 */
const props = withDefaults(defineProps<{
  /** full: day chips above a tall map. fill: just the map, filling its box. preview: a small map you can't move. */
  variant?: 'full' | 'fill' | 'preview'
  /** fill: the pin to zoom in on and select (an "a-…", "s-…", "tf-…" or "tt-…" key). */
  focus?: string | null
}>(), { variant: 'full', focus: null })
const emit = defineEmits<{ activity: [Activity]; stay: [Stay]; transport: [Transport]; select: [string | null] }>()
/** The day shown, as an index into the trip's days; null is every day. */
const dayIndex = defineModel<number | null>('day', { default: null })
const { trip, content } = useTripContext()
const { activities, stays, transport } = content

const days = computed(() => tripDays(trip.value.startDate, trip.value.endDate))
const day = computed(() => (dayIndex.value === null ? null : days.value[dayIndex.value] ?? null))

type Pin = {
  key: string
  kind: 'activity' | 'stay' | 'from' | 'to'
  title: string
  subtitle: string
  query: string
  coordinate: Coordinate | null
  open: () => void
}

const coord = (lat: number | null, lng: number | null): Coordinate | null => (lat !== null && lng !== null ? { latitude: lat, longitude: lng } : null)

const pins = computed<Pin[]>(() => {
  const d = day.value
  const list: Pin[] = []
  const dayActivities = activities.value.filter((a) => !d || isSameDay(a.date, d)).sort((a, b) => a.date.getTime() - b.date.getTime())
  dayActivities.forEach((a) => {
    list.push({ key: `a-${a.id}`, kind: 'activity', title: a.title, subtitle: a.location, query: a.location || a.title, coordinate: coord(a.latitude, a.longitude), open: () => emit('activity', a) })
  })
  for (const s of stays.value) {
    if (d && (d < new Date(s.startDate.toDateString()) || d > new Date(s.endDate.toDateString()))) continue
    list.push({ key: `s-${s.id}`, kind: 'stay', title: s.name, subtitle: s.location, query: s.location || s.name, coordinate: coord(s.latitude, s.longitude), open: () => emit('stay', s) })
  }
  for (const t of transport.value) {
    const departs = combine(t.departureDate, t.departureTime)
    const arrives = t.arrivalDate ? combine(t.arrivalDate, t.arrivalTime ?? '00:00') : departs
    if (d && !isSameDay(departs, d) && !isSameDay(arrives, d)) continue
    list.push({ key: `tf-${t.id}`, kind: 'from', title: t.departureLocation, subtitle: `Departs ${formatShort(t.departureDate)}`, query: t.departureLocation, coordinate: coord(t.departureLatitude, t.departureLongitude), open: () => emit('transport', t) })
    if (t.arrivalLocation) {
      list.push({ key: `tt-${t.id}`, kind: 'to', title: t.arrivalLocation, subtitle: `Arrival`, query: t.arrivalLocation, coordinate: coord(t.arrivalLatitude, t.arrivalLongitude), open: () => emit('transport', t) })
    }
  }
  return list
})

const el = ref<HTMLElement | null>(null)
const mapkit = shallowRef<MapKit | null>(null)
const map = shallowRef<MKMap | null>(null)
const error = ref<string | null>(null)
/** Places found by search because they had no pin saved. */
const found = ref<Record<string, Coordinate | null>>({})
const searching = ref(false)

const tripArea = computed(() => coord(trip.value.latitude, trip.value.longitude))
const unpinned = computed(() => pins.value.filter((p) => !p.coordinate && found.value[p.key] === null))

function themeColor(name: string, fallback: string): string {
  const root = el.value?.closest('[data-theme]') ?? document.documentElement
  return getComputedStyle(root).getPropertyValue(name).trim() || fallback
}

async function findMissing() {
  const mk = mapkit.value
  if (!mk) return
  const missing = pins.value.filter((p) => !p.coordinate && p.query && !(p.key in found.value))
  if (!missing.length) return
  searching.value = true
  for (const pin of missing) {
    const result = await geocode(mk, [pin.query, trip.value.location].filter(Boolean).join(', '), tripArea.value)
    found.value = { ...found.value, [pin.key]: result }
  }
  searching.value = false
}

function draw() {
  const mk = mapkit.value
  const m = map.value
  if (!mk || !m) return
  m.removeAnnotations(m.annotations)
  byKey.clear()
  m.removeOverlays(m.overlays)

  const accent = themeColor('--trip-500', '#f0a693')
  const dark = themeColor('--trip-700', '#c2654d')
  const annotations: MKAnnotation[] = []
  const route: Coordinate[] = []
  let number = 0
  for (const pin of pins.value) {
    const c = pin.coordinate ?? found.value[pin.key] ?? null
    if (pin.kind === 'activity') number++
    if (!c) continue
    const isActivity = pin.kind === 'activity'
    if (isActivity && day.value) route.push(c)
    const annotation = new mk.MarkerAnnotation(new mk.Coordinate(c.latitude, c.longitude), {
      title: pin.title,
      subtitle: pin.coordinate ? pin.subtitle : `${pin.subtitle ? `${pin.subtitle} · ` : ''}approximate`,
      color: isActivity ? accent : pin.kind === 'stay' ? dark : '#64748b',
      glyphText: isActivity && day.value ? String(number) : pin.kind === 'stay' ? '⌂' : pin.kind === 'activity' ? '' : pin.kind === 'from' ? '↗' : '↘',
      // Places found by search are guesses; show them a little lighter.
      opacity: pin.coordinate ? 1 : 0.75,
      data: { key: pin.key },
    })
    if (props.variant === 'fill') {
      // In the map view a pin selects its stop in the list; editing has its own button there.
      annotation.addEventListener('select', () => emit('select', pin.key))
    } else if (props.variant !== 'preview') {
      annotation.addEventListener('select', () => pin.open())
    }
    byKey.set(pin.key, annotation)
    annotations.push(annotation)
  }
  m.addAnnotations(annotations)
  const overlays: MKOverlay[] = []
  if (route.length > 1) {
    overlays.push(
      new mk.PolylineOverlay(
        route.map((c) => new mk.Coordinate(c.latitude, c.longitude)),
        { style: new mk.Style({ strokeColor: accent, lineWidth: 3, lineDash: [6, 6], strokeOpacity: 0.85 }) },
      ),
    )
    m.addOverlays(overlays)
  }
  if (props.focus && byKey.has(props.focus)) {
    byKey.get(props.focus)!.selected = true
  } else if (annotations.length) {
    m.showItems([...annotations, ...overlays], {
      animate: true,
      padding: new mk.Padding(60, 40, 40, 40),
      minimumSpan: new mk.CoordinateSpan(0.02, 0.02),
    })
  } else if (tripArea.value) {
    m.setCenterAnimated(new mk.Coordinate(tripArea.value.latitude, tripArea.value.longitude), true)
  }
}

const byKey = new Map<string, MKAnnotation>()

/** Zoom in on one pin and select it. */
function zoomTo(key: string | null) {
  const mk = mapkit.value
  const m = map.value
  if (!mk || !m || !key) return
  const annotation = byKey.get(key)
  if (!annotation) return
  const c = annotation.coordinate
  m.setRegionAnimated(new mk.CoordinateRegion(new mk.Coordinate(c.latitude, c.longitude), new mk.CoordinateSpan(0.006, 0.006)), true)
  annotation.selected = true
}

watch(() => props.focus, (key) => zoomTo(key))

onMounted(async () => {
  try {
    const mk = await loadMapKit()
    if (!el.value) return
    mapkit.value = mk
    mk.addEventListener('error', (event) => {
      error.value = event.status === 'Unauthorized' ? 'The map isn’t set up on the server yet.' : 'The map couldn’t load.'
    })
    const still = props.variant === 'preview'
    map.value = new mk.Map(el.value, {
      showsPointsOfInterest: !still,
      isRotationEnabled: false,
      ...(still ? { isScrollEnabled: false, isZoomEnabled: false, showsCompass: 'hidden', showsZoomControl: false, showsMapTypeControl: false } : {}),
    })
    draw()
    void findMissing()
  } catch (err) {
    error.value = (err as Error).message
  }
})

watch([pins, found], () => {
  draw()
  void findMissing()
})

onBeforeUnmount(() => map.value?.destroy())
</script>

<template>
  <div :class="variant === 'full' ? 'space-y-3' : 'relative h-full'">
    <nav v-if="variant === 'full'" class="-mx-4 flex gap-2 overflow-x-auto px-4 lg:mx-0 lg:px-0" aria-label="Map days">
      <button
        class="shrink-0 rounded-full border px-3 py-1.5 text-sm font-medium transition"
        :class="dayIndex === null ? 'border-trip-500 bg-trip-500 text-white' : 'border-trip-border bg-white hover:bg-trip-50'"
        @click="dayIndex = null"
      >All days</button>
      <button
        v-for="(d, i) in days"
        :key="d.getTime()"
        class="shrink-0 rounded-full border px-3 py-1.5 text-sm font-medium transition"
        :class="dayIndex === i ? 'border-trip-500 bg-trip-500 text-white' : 'border-trip-border bg-white hover:bg-trip-50'"
        @click="dayIndex = i"
      >Day {{ i + 1 }} <span class="opacity-70">· {{ formatShort(d) }}</span></button>
    </nav>

    <div :class="variant === 'full' ? 'sticker-card-trip relative overflow-hidden rounded-card-sm' : 'relative h-full'">
      <div
        ref="el"
        class="w-full bg-card-surface"
        :class="variant === 'full' ? 'h-[60dvh] min-h-80 lg:h-[calc(100dvh-22rem)]' : 'h-full min-h-48'"
      />
      <div v-if="error" class="absolute inset-0 flex items-center justify-center bg-card-surface p-6 text-center">
        <p class="text-sm text-zinc-600">{{ error }}</p>
      </div>
      <p v-else-if="!pins.length" class="absolute top-3 left-1/2 -translate-x-1/2 rounded-full bg-white/90 px-3 py-1.5 text-sm shadow">
        Nothing planned {{ day ? 'this day' : 'yet' }}.
      </p>
    </div>

    <p v-if="searching && variant !== 'preview'" class="text-xs text-zinc-500" :class="variant === 'fill' ? 'absolute bottom-3 left-3 rounded-full bg-white/90 px-3 py-1.5' : ''">Finding places without a pin…</p>
    <div
      v-if="unpinned.length && variant !== 'preview'"
      class="rounded-dense p-3 text-sm"
      :class="variant === 'fill' ? 'absolute top-3 left-3 max-w-80 border border-secondary bg-white/90 backdrop-blur' : 'bg-card-surface'"
    >
      <p class="flex items-center gap-1.5 font-medium"><PhMapPinLine class="size-4" /> Not on the map</p>
      <p class="mt-1 text-zinc-600">
        Couldn’t find {{ unpinned.map((p) => p.title).join(', ') }}. Pick the place in the iPhone app to pin it.
      </p>
    </div>
  </div>
</template>
