<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import AppDialog from './AppDialog.vue'
import { parseAmount } from '@/lib/money'
import { setMemberBudget } from '@/lib/writes'
import { useTripContext } from '@/composables/tripContext'

const props = defineProps<{ uid: string | null }>()
const open = defineModel<boolean>('open', { required: true })
const { trip, name } = useTripContext()

const amount = ref('')
const saving = ref(false)
const error = ref<string | null>(null)

watch(open, (isOpen) => {
  if (!isOpen || !props.uid) return
  const current = trip.value.memberBudgets[props.uid]
  amount.value = current ? String(current) : ''
  error.value = null
})

const parsed = computed(() => parseAmount(amount.value))

async function save() {
  if (!props.uid || parsed.value === undefined) return
  saving.value = true
  try {
    await setMemberBudget(trip.value.id, props.uid, parsed.value ?? 0)
    open.value = false
  } catch (err) {
    console.error(err)
    error.value = 'Couldn’t save. Check your connection and try again.'
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <AppDialog v-model:open="open" :title="`${name(uid)} · budget`" description="What this person plans to spend on their own." :theme="trip.theme">
    <form id="member-budget-form" @submit.prevent="save">
      <label class="label" for="member-budget">Amount ({{ trip.currency }})</label>
      <input id="member-budget" v-model="amount" type="number" min="0" step="any" inputmode="decimal" class="input" placeholder="0" />
      <p v-if="error" class="mt-2 text-sm text-danger">{{ error }}</p>
    </form>
    <template #footer>
      <button type="submit" form="member-budget-form" class="btn-primary ml-auto" :disabled="parsed === undefined || saving">{{ saving ? 'Saving…' : 'Save' }}</button>
    </template>
  </AppDialog>
</template>
