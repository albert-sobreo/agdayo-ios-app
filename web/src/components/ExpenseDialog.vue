<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { PhTrash } from '@phosphor-icons/vue'
import AppDialog from './AppDialog.vue'
import CostSplitFields from './CostSplitFields.vue'
import ExchangeRateField from './ExchangeRateField.vue'
import type { Expense } from '@/lib/model'
import { currencies, parseAmount } from '@/lib/money'
import { fromDateInput, toDateInput } from '@/lib/dates'
import { deleteItem, saveExpense, splitOf, type SplitInput } from '@/lib/writes'
import { useTripContext } from '@/composables/tripContext'

/** An expense that isn't an activity, stay or ride (ExpenseEditSheet in the app). */
const props = defineProps<{ expense?: Expense }>()
const open = defineModel<boolean>('open', { required: true })
const { trip, content, people, uid } = useTripContext()

const name = ref('')
const amount = ref('')
const currency = ref('PHP')
const rate = ref<number | null>(null)
const dayInput = ref('')
const time = ref('')
const split = ref<SplitInput>(splitOf(undefined))
const saving = ref(false)
const error = ref<string | null>(null)

watch(open, (isOpen) => {
  if (!isOpen) return
  const e = props.expense
  name.value = e?.name ?? ''
  amount.value = e ? String(e.cost) : ''
  currency.value = e?.costCurrency ?? trip.value.currency
  rate.value = e?.exchangeRateToTripCurrency ?? null
  dayInput.value = e?.date ? toDateInput(e.date) : ''
  time.value = e?.time ?? ''
  split.value = splitOf(e)
  // New expenses: you paid, split with everyone (like the app).
  if (!e && people.value.length > 1) {
    split.value.paidByUID = uid.value
    split.value.splitUIDs = people.value.map((p) => p.uid)
  }
  error.value = null
})

const parsed = computed(() => parseAmount(amount.value))
const valid = computed(() => name.value.trim() && typeof parsed.value === 'number' && parsed.value > 0)
const allCurrencies = computed(() => (currencies.includes(currency.value) ? currencies : [currency.value, ...currencies]))

async function save() {
  if (!valid.value) return
  saving.value = true
  try {
    await saveExpense(trip.value.id, props.expense, {
      name: name.value.trim(),
      date: dayInput.value ? fromDateInput(dayInput.value) : null,
      time: dayInput.value && time.value ? time.value : null,
      cost: parsed.value as number,
      costCurrency: currency.value,
      exchangeRateToTripCurrency: currency.value === trip.value.currency ? null : rate.value,
      split: split.value.paidByUID ? split.value : { ...split.value, splitUIDs: [], splitAmounts: {} },
    })
    open.value = false
  } catch (err) {
    console.error(err)
    error.value = 'Couldn’t save. Check your connection and try again.'
  } finally {
    saving.value = false
  }
}

async function remove() {
  if (!props.expense || !window.confirm(`Delete “${props.expense.name}”?`)) return
  saving.value = true
  try {
    await deleteItem(trip.value.id, 'expenses', props.expense.id)
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
  <AppDialog v-model:open="open" :title="expense ? 'Edit expense' : 'New expense'" :theme="trip.theme">
    <form id="expense-form" class="space-y-4" @submit.prevent="save">
      <div>
        <label class="label" for="expense-name">What</label>
        <input id="expense-name" v-model="name" class="input" placeholder="Souvenirs" required />
      </div>
      <div class="grid grid-cols-[1fr_7rem] gap-3">
        <div>
          <label class="label" for="expense-amount">Amount</label>
          <input id="expense-amount" v-model="amount" type="number" min="0" step="any" inputmode="decimal" class="input" placeholder="0" required />
        </div>
        <div>
          <label class="label" for="expense-currency">Currency</label>
          <select id="expense-currency" v-model="currency" class="input" @change="rate = null">
            <option v-for="code in allCurrencies" :key="code" :value="code">{{ code }}</option>
          </select>
        </div>
      </div>
      <ExchangeRateField v-model="rate" :from="currency" :to="trip.currency" :amount="parsed || 0" />
      <div class="grid grid-cols-[1fr_auto] gap-3">
        <div>
          <label class="label" for="expense-day">Date</label>
          <input id="expense-day" v-model="dayInput" type="date" class="input" :min="toDateInput(trip.startDate)" :max="toDateInput(trip.endDate)" />
        </div>
        <div>
          <label class="label" for="expense-time">Time</label>
          <input id="expense-time" v-model="time" type="time" class="input" :disabled="!dayInput" />
        </div>
      </div>
      <CostSplitFields v-model="split" :people="people" :categories="content.budgetCategories.value" :total="parsed || 0" :currency="currency" />
      <p v-if="error" class="text-sm text-danger">{{ error }}</p>
    </form>
    <template #footer>
      <button v-if="expense" type="button" class="btn-danger" :disabled="saving" @click="remove"><PhTrash class="size-4" /> Delete</button>
      <button type="submit" form="expense-form" class="btn-primary ml-auto" :disabled="!valid || saving">{{ saving ? 'Saving…' : 'Save' }}</button>
    </template>
  </AppDialog>
</template>
