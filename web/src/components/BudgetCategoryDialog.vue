<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { PhTrash } from '@phosphor-icons/vue'
import AppDialog from './AppDialog.vue'
import type { BudgetCategory } from '@/lib/model'
import { parseAmount } from '@/lib/money'
import { deleteBudgetCategory, saveBudgetCategory } from '@/lib/writes'
import { useTripContext } from '@/composables/tripContext'

const props = defineProps<{ category?: BudgetCategory }>()
const open = defineModel<boolean>('open', { required: true })
const { trip, content } = useTripContext()

const suggestions = ['Food', 'Activities', 'Shopping', 'Transportation', 'Accommodation', 'Souvenirs', 'Tips', 'Emergency']
const name = ref('')
const amount = ref('')
const saving = ref(false)
const error = ref<string | null>(null)

watch(open, (isOpen) => {
  if (!isOpen) return
  name.value = props.category?.name ?? ''
  amount.value = props.category ? String(props.category.amount) : ''
  error.value = null
})

const parsed = computed(() => parseAmount(amount.value))
const valid = computed(() => name.value.trim() && typeof parsed.value === 'number')
const othersTotal = computed(() => content.budgetCategories.value.filter((c) => c.id !== props.category?.id).reduce((t, c) => t + c.amount, 0))

async function save() {
  if (!valid.value) return
  saving.value = true
  try {
    const value = parsed.value as number
    await saveBudgetCategory(trip.value.id, props.category?.id ?? null, { name: name.value.trim(), amount: value }, othersTotal.value + value)
    open.value = false
  } catch (err) {
    console.error(err)
    error.value = 'Couldn’t save. Check your connection and try again.'
  } finally {
    saving.value = false
  }
}

async function remove() {
  if (!props.category || !window.confirm(`Delete “${props.category.name}”?`)) return
  saving.value = true
  try {
    await deleteBudgetCategory(trip.value.id, props.category.id, othersTotal.value)
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
  <AppDialog v-model:open="open" :title="category ? 'Edit category' : 'New category'" description="Categories add up to the trip’s budget." :theme="trip.theme">
    <form id="category-form" class="space-y-4" @submit.prevent="save">
      <div>
        <label class="label" for="category-name">Name</label>
        <input id="category-name" v-model="name" class="input" placeholder="Food" required />
        <div v-if="!category" class="mt-2 flex flex-wrap gap-1.5">
          <button v-for="s in suggestions" :key="s" type="button" class="rounded-full border border-trip-border bg-white px-2.5 py-1 text-xs hover:bg-trip-50" @click="name = s">{{ s }}</button>
        </div>
      </div>
      <div>
        <label class="label" for="category-amount">Planned amount ({{ trip.currency }})</label>
        <input id="category-amount" v-model="amount" type="number" min="0" step="any" inputmode="decimal" class="input" placeholder="0" required />
      </div>
      <p v-if="error" class="text-sm text-danger">{{ error }}</p>
    </form>
    <template #footer>
      <button v-if="category" type="button" class="btn-danger" :disabled="saving" @click="remove"><PhTrash class="size-4" /> Delete</button>
      <button type="submit" form="category-form" class="btn-primary ml-auto" :disabled="!valid || saving">{{ saving ? 'Saving…' : 'Save' }}</button>
    </template>
  </AppDialog>
</template>
