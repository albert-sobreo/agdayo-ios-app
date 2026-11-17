<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { PhTrash } from '@phosphor-icons/vue'
import AppDialog from './AppDialog.vue'
import CostSplitFields from './CostSplitFields.vue'
import ExchangeRateField from './ExchangeRateField.vue'
import { transportModeNames, transportModes, type Transport, type TransportMode, type Trip } from '@/lib/model'
import { combine, fromDateInput, toDateInput } from '@/lib/dates'
import { addTransport, deleteItem, splitOf, updateTransport, type SplitInput } from '@/lib/writes'
import { currencies } from '@/lib/money'
import { useTripContext } from '@/composables/tripContext'

const props = defineProps<{ trip: Trip; segment?: Transport; day?: Date }>()
const open = defineModel<boolean>('open', { required: true })

const mode = ref<TransportMode>('flight')
const from = ref('')
const to = ref('')
const departDay = ref('')
const departTime = ref('08:00')
const hasArrival = ref(false)
const arriveDay = ref('')
const arriveTime = ref('10:00')
const bookingRef = ref('')
const seat = ref('')
const notes = ref('')
const cost = ref('')
const currency = ref('PHP')
const rate = ref<number | null>(null)
const split = ref<SplitInput>(splitOf(undefined))
const { content, people } = useTripContext()
const saving = ref(false)
const error = ref<string | null>(null)

watch(open, (isOpen) => {
  if (!isOpen) return
  const s = props.segment
  mode.value = s?.mode ?? 'flight'
  from.value = s?.departureLocation ?? ''
  to.value = s?.arrivalLocation ?? ''
  departDay.value = toDateInput(s?.departureDate ?? props.day ?? props.trip.startDate)
  departTime.value = s?.departureTime ?? '08:00'
  hasArrival.value = !!s?.arrivalDate
  arriveDay.value = toDateInput(s?.arrivalDate ?? s?.departureDate ?? props.day ?? props.trip.startDate)
  arriveTime.value = s?.arrivalTime ?? '10:00'
  bookingRef.value = s?.bookingRef ?? ''
  seat.value = s?.seatNumber ?? ''
  notes.value = s?.notes ?? ''
  cost.value = s?.cost ? String(s.cost) : ''
  currency.value = s?.currency ?? props.trip.currency
  rate.value = s?.exchangeRateToTripCurrency ?? null
  split.value = splitOf(s)
  error.value = null
})

const allCurrencies = computed(() => (currencies.includes(currency.value) ? currencies : [currency.value, ...currencies]))
const arrivalBeforeDeparture = computed(
  () =>
    hasArrival.value &&
    combine(fromDateInput(arriveDay.value), arriveTime.value) < combine(fromDateInput(departDay.value), departTime.value),
)
const valid = computed(
  () => from.value.trim() && to.value.trim() && departDay.value && departTime.value && !arrivalBeforeDeparture.value && Number(cost.value || 0) >= 0,
)

async function save() {
  if (!valid.value) return
  saving.value = true
  error.value = null
  const input = {
    mode: mode.value,
    departureLocation: from.value.trim(),
    departureDate: fromDateInput(departDay.value),
    departureTime: departTime.value,
    arrivalLocation: to.value.trim(),
    arrivalDate: hasArrival.value ? fromDateInput(arriveDay.value) : null,
    arrivalTime: hasArrival.value ? arriveTime.value : null,
    bookingRef: bookingRef.value.trim(),
    seatNumber: seat.value.trim(),
    notes: notes.value.trim(),
    cost: Number(cost.value || 0),
    currency: currency.value,
    exchangeRateToTripCurrency: currency.value !== props.trip.currency && Number(cost.value || 0) > 0 ? rate.value : null,
    split: Number(cost.value || 0) > 0 && split.value.paidByUID ? split.value : { ...split.value, paidByUID: null, splitUIDs: [], splitAmounts: {} },
  }
  try {
    if (props.segment) {
      await updateTransport(props.trip.id, props.segment.id, input, {
        from: input.departureLocation !== props.segment.departureLocation,
        to: input.arrivalLocation !== props.segment.arrivalLocation,
      })
    } else {
      await addTransport(props.trip.id, input)
    }
    open.value = false
  } catch (err) {
    console.error(err)
    error.value = 'Couldn’t save. Check your connection and try again.'
  } finally {
    saving.value = false
  }
}

async function remove() {
  if (!props.segment || !window.confirm('Delete this transport?')) return
  saving.value = true
  try {
    await deleteItem(props.trip.id, 'transportSegments', props.segment.id)
    open.value = false
  } catch (err) {
    console.error(err)
    error.value = 'Couldn’t delete. Check your connection and try again.'
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <AppDialog v-model:open="open" :title="segment ? 'Edit transport' : 'New transport'" :theme="trip.theme">
    <form id="transport-form" class="space-y-4" @submit.prevent="save">
      <div>
        <label class="label" for="transport-mode">How</label>
        <select id="transport-mode" v-model="mode" class="input">
          <option v-for="option in transportModes" :key="option" :value="option">{{ transportModeNames[option] }}</option>
        </select>
      </div>
      <div class="grid grid-cols-2 gap-3">
        <div>
          <label class="label" for="transport-from">From</label>
          <input id="transport-from" v-model="from" class="input" placeholder="NAIA Terminal 3" required />
        </div>
        <div>
          <label class="label" for="transport-to">To</label>
          <input id="transport-to" v-model="to" class="input" placeholder="Changi Airport" required />
        </div>
      </div>
      <div class="grid grid-cols-[1fr_auto] gap-3">
        <div>
          <label class="label" for="transport-depart">Departs</label>
          <input id="transport-depart" v-model="departDay" type="date" class="input" required />
        </div>
        <div>
          <label class="label" for="transport-depart-time">Time</label>
          <input id="transport-depart-time" v-model="departTime" type="time" class="input" required />
        </div>
      </div>
      <label class="flex items-center gap-2 text-sm font-medium text-zinc-700">
        <input v-model="hasArrival" type="checkbox" class="size-4 accent-ink" /> Add arrival time
      </label>
      <div v-if="hasArrival" class="grid grid-cols-[1fr_auto] gap-3">
        <div>
          <label class="label" for="transport-arrive">Arrives</label>
          <input id="transport-arrive" v-model="arriveDay" type="date" :min="departDay" class="input" />
        </div>
        <div>
          <label class="label" for="transport-arrive-time">Time</label>
          <input id="transport-arrive-time" v-model="arriveTime" type="time" class="input" />
        </div>
      </div>
      <p v-if="arrivalBeforeDeparture" class="text-sm text-danger">The arrival is before the departure.</p>
      <div class="grid grid-cols-2 gap-3">
        <div>
          <label class="label" for="transport-ref">Booking ref</label>
          <input id="transport-ref" v-model="bookingRef" class="input" placeholder="Optional" />
        </div>
        <div>
          <label class="label" for="transport-seat">Seat</label>
          <input id="transport-seat" v-model="seat" class="input" placeholder="Optional" />
        </div>
      </div>
      <div class="grid grid-cols-[1fr_7rem] gap-3">
        <div>
          <label class="label" for="transport-cost">Cost</label>
          <input id="transport-cost" v-model="cost" type="number" min="0" step="any" inputmode="decimal" class="input" placeholder="0" />
        </div>
        <div>
          <label class="label" for="transport-currency">Currency</label>
          <select id="transport-currency" v-model="currency" class="input" @change="rate = null">
            <option v-for="code in allCurrencies" :key="code" :value="code">{{ code }}</option>
          </select>
        </div>
      </div>
      <template v-if="Number(cost || 0) > 0">
        <ExchangeRateField v-model="rate" :from="currency" :to="trip.currency" :amount="Number(cost || 0)" />
        <CostSplitFields v-model="split" :people="people" :categories="content.budgetCategories.value" :total="Number(cost || 0)" :currency="currency" />
      </template>
      <div>
        <label class="label" for="transport-notes">Notes</label>
        <textarea id="transport-notes" v-model="notes" rows="2" class="input" placeholder="Optional" />
      </div>
      <p v-if="error" class="text-sm text-danger">{{ error }}</p>
    </form>
    <template #footer>
      <button v-if="segment" type="button" class="btn-danger" :disabled="saving" @click="remove"><PhTrash class="size-4" /> Delete</button>
      <button type="submit" form="transport-form" class="btn-primary ml-auto" :disabled="!valid || saving">{{ saving ? 'Saving…' : 'Save' }}</button>
    </template>
  </AppDialog>
</template>
