<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { PhTrash } from '@phosphor-icons/vue'
import AppDialog from './AppDialog.vue'
import CostSplitFields from './CostSplitFields.vue'
import { stayTypeNames, stayTypes, type Stay, type StayType, type Trip } from '@/lib/model'
import { fromDateInput, toDateInput } from '@/lib/dates'
import { addStay, deleteItem, splitOf, updateStay, type SplitInput } from '@/lib/writes'
import { useTripContext } from '@/composables/tripContext'

const props = defineProps<{ trip: Trip; stay?: Stay }>()
const open = defineModel<boolean>('open', { required: true })

const name = ref('')
const type = ref<StayType>('hotel')
const location = ref('')
const checkIn = ref('')
const checkInTime = ref('15:00')
const checkOut = ref('')
const checkOutTime = ref('11:00')
const rooms = ref('1')
const totalCost = ref('')
const split = ref<SplitInput>(splitOf(undefined))
const { content, people } = useTripContext()
const saving = ref(false)
const error = ref<string | null>(null)

watch(open, (isOpen) => {
  if (!isOpen) return
  const s = props.stay
  name.value = s?.name ?? ''
  type.value = s?.type ?? 'hotel'
  location.value = s?.location ?? ''
  checkIn.value = toDateInput(s?.startDate ?? props.trip.startDate)
  checkOut.value = toDateInput(s?.endDate ?? props.trip.endDate)
  checkInTime.value = s?.checkInTime ?? '15:00'
  checkOutTime.value = s?.checkOutTime ?? '11:00'
  rooms.value = String(s?.numberOfRooms ?? 1)
  totalCost.value = s?.totalCost ? String(s.totalCost) : ''
  split.value = splitOf(s)
  error.value = null
})

const valid = computed(
  () =>
    name.value.trim() &&
    checkIn.value &&
    checkOut.value &&
    checkOut.value >= checkIn.value &&
    Number.isInteger(Number(rooms.value)) &&
    Number(rooms.value) >= 1 &&
    Number(totalCost.value || 0) >= 0,
)

async function save() {
  if (!valid.value) return
  saving.value = true
  error.value = null
  const input = {
    name: name.value.trim(),
    type: type.value,
    location: location.value.trim(),
    numberOfRooms: Number(rooms.value),
    totalCost: Number(totalCost.value || 0),
    checkInTime: checkInTime.value,
    checkOutTime: checkOutTime.value,
    startDate: fromDateInput(checkIn.value),
    endDate: fromDateInput(checkOut.value),
    split: Number(totalCost.value || 0) > 0 && split.value.paidByUID ? split.value : { ...split.value, paidByUID: null, splitUIDs: [], splitAmounts: {} },
  }
  try {
    if (props.stay) await updateStay(props.trip.id, props.stay.id, input, input.location !== props.stay.location)
    else await addStay(props.trip.id, input)
    open.value = false
  } catch (err) {
    console.error(err)
    error.value = 'Couldn’t save. Check your connection and try again.'
  } finally {
    saving.value = false
  }
}

async function remove() {
  if (!props.stay || !window.confirm(`Delete “${props.stay.name}”?`)) return
  saving.value = true
  try {
    await deleteItem(props.trip.id, 'accommodations', props.stay.id)
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
  <AppDialog v-model:open="open" :title="stay ? 'Edit stay' : 'New stay'" :theme="trip.theme">
    <form id="stay-form" class="space-y-4" @submit.prevent="save">
      <div>
        <label class="label" for="stay-name">Name</label>
        <input id="stay-name" v-model="name" class="input" placeholder="The Manor at Camp John Hay" required />
      </div>
      <div class="grid grid-cols-2 gap-3">
        <div>
          <label class="label" for="stay-type">Type</label>
          <select id="stay-type" v-model="type" class="input">
            <option v-for="option in stayTypes" :key="option" :value="option">{{ stayTypeNames[option] }}</option>
          </select>
        </div>
        <div>
          <label class="label" for="stay-rooms">Rooms</label>
          <input id="stay-rooms" v-model="rooms" type="number" min="1" step="1" class="input" />
        </div>
      </div>
      <div>
        <label class="label" for="stay-location">Address</label>
        <input id="stay-location" v-model="location" class="input" placeholder="Optional" />
      </div>
      <div class="grid grid-cols-[1fr_auto] gap-3">
        <div>
          <label class="label" for="stay-in">Check-in</label>
          <input id="stay-in" v-model="checkIn" type="date" class="input" :min="toDateInput(trip.startDate)" :max="toDateInput(trip.endDate)" />
        </div>
        <div>
          <label class="label" for="stay-in-time">Time</label>
          <input id="stay-in-time" v-model="checkInTime" type="time" class="input" />
        </div>
      </div>
      <div class="grid grid-cols-[1fr_auto] gap-3">
        <div>
          <label class="label" for="stay-out">Check-out</label>
          <input id="stay-out" v-model="checkOut" type="date" class="input" :min="checkIn" :max="toDateInput(trip.endDate)" />
        </div>
        <div>
          <label class="label" for="stay-out-time">Time</label>
          <input id="stay-out-time" v-model="checkOutTime" type="time" class="input" />
        </div>
      </div>
      <div>
        <label class="label" for="stay-cost">Total cost ({{ trip.currency }})</label>
        <input id="stay-cost" v-model="totalCost" type="number" min="0" step="any" inputmode="decimal" class="input" placeholder="0" />
      </div>
      <div v-if="Number(totalCost || 0) > 0">
        <CostSplitFields v-model="split" :people="people" :categories="content.budgetCategories.value" :total="Number(totalCost || 0)" :currency="trip.currency" />
      </div>
      <p v-if="error" class="text-sm text-danger">{{ error }}</p>
    </form>
    <template #footer>
      <button v-if="stay" type="button" class="btn-danger" :disabled="saving" @click="remove"><PhTrash class="size-4" /> Delete</button>
      <button type="submit" form="stay-form" class="btn-primary ml-auto" :disabled="!valid || saving">{{ saving ? 'Saving…' : 'Save' }}</button>
    </template>
  </AppDialog>
</template>
