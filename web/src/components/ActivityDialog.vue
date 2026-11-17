<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { PhTrash } from '@phosphor-icons/vue'
import AppDialog from './AppDialog.vue'
import type { Activity, Trip } from '@/lib/model'
import { activityIcons } from '@/lib/icons'
import { combine, fromDateInput, toDateInput, toTimeInput } from '@/lib/dates'
import { addActivity, deleteItem, updateActivity } from '@/lib/writes'

const props = defineProps<{ trip: Trip; activity?: Activity; day?: Date }>()
const open = defineModel<boolean>('open', { required: true })

const title = ref('')
const dayInput = ref('')
const time = ref('09:00')
const location = ref('')
const iconName = ref('mappin.and.ellipse')
const description = ref('')
const cost = ref('')
const costNote = ref('')
const saving = ref(false)
const error = ref<string | null>(null)

watch(open, (isOpen) => {
  if (!isOpen) return
  const a = props.activity
  title.value = a?.title ?? ''
  dayInput.value = toDateInput(a?.date ?? props.day ?? props.trip.startDate)
  time.value = a ? toTimeInput(a.date) : '09:00'
  location.value = a?.location ?? ''
  iconName.value = a?.iconName ?? 'mappin.and.ellipse'
  description.value = a?.activityDescription ?? ''
  cost.value = a?.cost != null ? String(a.cost) : ''
  costNote.value = a?.costNote ?? ''
  error.value = null
})

/** An activity priced in another currency keeps it, so its exchange rate stays right. */
const costCurrency = computed(() => props.activity?.costCurrency ?? props.trip.currency)
const parsedCost = computed(() => (cost.value.trim() === '' ? null : Number(cost.value)))
const valid = computed(
  () => title.value.trim() && dayInput.value && time.value && (parsedCost.value === null || (Number.isFinite(parsedCost.value) && parsedCost.value >= 0)),
)

async function save() {
  if (!valid.value) return
  saving.value = true
  error.value = null
  const input = {
    title: title.value.trim(),
    location: location.value.trim(),
    date: combine(fromDateInput(dayInput.value), time.value),
    activityDescription: description.value.trim(),
    iconName: iconName.value,
    cost: parsedCost.value,
    costCurrency: costCurrency.value,
    costNote: costNote.value.trim(),
  }
  try {
    if (props.activity) await updateActivity(props.trip.id, props.activity.id, input, input.location !== props.activity.location)
    else await addActivity(props.trip.id, input)
    open.value = false
  } catch (err) {
    console.error(err)
    error.value = 'Couldn’t save. Check your connection and try again.'
  } finally {
    saving.value = false
  }
}

async function remove() {
  if (!props.activity || !window.confirm(`Delete “${props.activity.title}”?`)) return
  saving.value = true
  try {
    await deleteItem(props.trip.id, 'activities', props.activity.id)
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
  <AppDialog v-model:open="open" :title="activity ? 'Edit activity' : 'New activity'" :theme="trip.theme">
    <form id="activity-form" class="space-y-4" @submit.prevent="save">
      <div>
        <label class="label" for="activity-title">What</label>
        <input id="activity-title" v-model="title" class="input" placeholder="Breakfast at Café by the Ruins" required />
      </div>
      <div class="grid grid-cols-[1fr_auto] gap-3">
        <div>
          <label class="label" for="activity-day">Day</label>
          <input id="activity-day" v-model="dayInput" type="date" class="input" :min="toDateInput(trip.startDate)" :max="toDateInput(trip.endDate)" required />
        </div>
        <div>
          <label class="label" for="activity-time">Time</label>
          <input id="activity-time" v-model="time" type="time" class="input" required />
        </div>
      </div>
      <div>
        <label class="label" for="activity-location">Where</label>
        <input id="activity-location" v-model="location" class="input" placeholder="Optional" />
      </div>
      <div>
        <span class="label">Icon</span>
        <div class="max-h-44 space-y-2 overflow-y-auto rounded-xl border border-secondary bg-white p-2">
          <div v-for="group in activityIcons" :key="group.name" class="flex flex-wrap gap-1">
            <button
              v-for="item in group.icons"
              :key="item.symbol"
              type="button"
              class="flex size-9 items-center justify-center rounded-lg transition"
              :class="iconName === item.symbol ? 'bg-trip-500 text-white' : 'text-zinc-600 hover:bg-trip-50'"
              :aria-label="item.symbol"
              :aria-pressed="iconName === item.symbol"
              @click="iconName = item.symbol"
            >
              <component :is="item.icon" class="size-4.5" />
            </button>
          </div>
        </div>
      </div>
      <div>
        <label class="label" for="activity-notes">Notes</label>
        <textarea id="activity-notes" v-model="description" rows="3" class="input" placeholder="Optional" />
      </div>
      <div class="grid grid-cols-2 gap-3">
        <div>
          <label class="label" for="activity-cost">Cost ({{ costCurrency }})</label>
          <input id="activity-cost" v-model="cost" type="number" min="0" step="any" inputmode="decimal" class="input" placeholder="0" />
        </div>
        <div>
          <label class="label" for="activity-cost-note">Cost note</label>
          <input id="activity-cost-note" v-model="costNote" class="input" placeholder="per person" />
        </div>
      </div>
      <p v-if="error" class="text-sm text-danger">{{ error }}</p>
    </form>
    <template #footer>
      <button v-if="activity" type="button" class="btn-danger" :disabled="saving" @click="remove"><PhTrash class="size-4" /> Delete</button>
      <button type="submit" form="activity-form" class="btn-primary ml-auto" :disabled="!valid || saving">{{ saving ? 'Saving…' : 'Save' }}</button>
    </template>
  </AppDialog>
</template>
