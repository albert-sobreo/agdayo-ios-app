<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { PhTrash } from '@phosphor-icons/vue'
import AppDialog from './AppDialog.vue'
import CostSplitFields from './CostSplitFields.vue'
import ExchangeRateField from './ExchangeRateField.vue'
import type { Activity, Trip } from '@/lib/model'
import { activityIcons } from '@/lib/icons'
import { combine, fromDateInput, toDateInput, toTimeInput } from '@/lib/dates'
import { addActivity, deleteItem, splitOf, updateActivity, type SplitInput } from '@/lib/writes'
import { currencies } from '@/lib/money'
import { useTripContext } from '@/composables/tripContext'

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
const costCurrency = ref('PHP')
const rate = ref<number | null>(null)
const split = ref<SplitInput>(splitOf(undefined))
const { content, people, uid } = useTripContext()
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
  costCurrency.value = a?.costCurrency ?? props.trip.currency
  rate.value = a?.exchangeRateToTripCurrency ?? null
  split.value = splitOf(a)
  error.value = null
})

const allCurrencies = computed(() => (currencies.includes(costCurrency.value) ? currencies : [costCurrency.value, ...currencies]))
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
    exchangeRateToTripCurrency: parsedCost.value !== null && costCurrency.value !== props.trip.currency ? rate.value : null,
    split: parsedCost.value !== null && split.value.paidByUID ? split.value : { ...split.value, paidByUID: null, splitUIDs: [], splitAmounts: {} },
  }
  try {
    if (props.activity) await updateActivity(props.trip.id, props.activity.id, input, input.location !== props.activity.location)
    else await addActivity(props.trip.id, input, uid.value)
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
      <div class="grid grid-cols-[1fr_7rem] gap-3">
        <div>
          <label class="label" for="activity-cost">Cost</label>
          <input id="activity-cost" v-model="cost" type="number" min="0" step="any" inputmode="decimal" class="input" placeholder="Optional" />
        </div>
        <div>
          <label class="label" for="activity-currency">Currency</label>
          <select id="activity-currency" v-model="costCurrency" class="input" @change="rate = null">
            <option v-for="code in allCurrencies" :key="code" :value="code">{{ code }}</option>
          </select>
        </div>
      </div>
      <template v-if="parsedCost !== null">
        <ExchangeRateField v-model="rate" :from="costCurrency" :to="trip.currency" :amount="parsedCost || 0" />
        <div>
          <label class="label" for="activity-cost-note">Cost note</label>
          <input id="activity-cost-note" v-model="costNote" class="input" placeholder="per person" />
        </div>
        <CostSplitFields v-model="split" :people="people" :categories="content.budgetCategories.value" :total="parsedCost || 0" :currency="costCurrency" />
      </template>
      <p v-if="error" class="text-sm text-danger">{{ error }}</p>
    </form>
    <template #footer>
      <button v-if="activity" type="button" class="btn-danger" :disabled="saving" @click="remove"><PhTrash class="size-4" /> Delete</button>
      <button type="submit" form="activity-form" class="btn-primary ml-auto" :disabled="!valid || saving">{{ saving ? 'Saving…' : 'Save' }}</button>
    </template>
  </AppDialog>
</template>
