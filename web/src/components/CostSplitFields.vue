<script setup lang="ts">
import { computed } from 'vue'
import type { BudgetCategory } from '@/lib/model'
import type { SplitInput } from '@/lib/writes'
import { formatMoney } from '@/lib/dates'

/**
 * "Budget", "Paid by" and "Split" for a cost, like the app's BudgetCategoryPicker
 * and ExpenseSplitSection. Split is hidden on solo trips.
 */
const props = defineProps<{
  people: { uid: string; name: string }[]
  categories: BudgetCategory[]
  total: number
  currency: string
}>()
const split = defineModel<SplitInput>({ required: true })

/** One select for both: a category, a person's budget, or none. */
const budgetValue = computed({
  get: () => (split.value.budgetCategoryID ? `c:${split.value.budgetCategoryID}` : split.value.budgetMemberUID ? `m:${split.value.budgetMemberUID}` : ''),
  set: (value: string) => {
    split.value = {
      ...split.value,
      budgetCategoryID: value.startsWith('c:') ? value.slice(2) : null,
      budgetMemberUID: value.startsWith('m:') ? value.slice(2) : null,
    }
  },
})

const isCustom = computed(() => Object.keys(split.value.splitAmounts).length > 0)
const customTotal = computed(() => Object.values(split.value.splitAmounts).reduce((a, b) => a + b, 0))

function setPaidBy(value: string) {
  split.value = { ...split.value, paidByUID: value || null }
}

function toggle(uid: string) {
  const on = split.value.splitUIDs.includes(uid)
  const splitUIDs = on ? split.value.splitUIDs.filter((u) => u !== uid) : [...split.value.splitUIDs, uid]
  const splitAmounts = { ...split.value.splitAmounts }
  if (on) delete splitAmounts[uid]
  else if (isCustom.value) splitAmounts[uid] = 0
  split.value = { ...split.value, splitUIDs, splitAmounts }
}

function setCustom(custom: boolean) {
  if (!custom) {
    split.value = { ...split.value, splitAmounts: {} }
    return
  }
  // Start from an even split, rounded to the cent, with the leftover cents on the last person.
  const uids = [...split.value.splitUIDs].sort()
  const amounts: Record<string, number> = {}
  if (uids.length) {
    const share = Math.floor((props.total / uids.length) * 100) / 100
    uids.slice(0, -1).forEach((uid) => (amounts[uid] = share))
    amounts[uids[uids.length - 1]!] = Math.round((props.total - share * (uids.length - 1)) * 100) / 100
  }
  split.value = { ...split.value, splitAmounts: amounts }
}

function setAmount(uid: string, text: string) {
  const value = Number(text)
  split.value = { ...split.value, splitAmounts: { ...split.value.splitAmounts, [uid]: Number.isFinite(value) && value >= 0 ? value : 0 } }
}
</script>

<template>
  <div class="space-y-4">
    <div v-if="categories.length || people.length > 1">
      <label class="label" for="split-budget">Budget</label>
      <select id="split-budget" v-model="budgetValue" class="input">
        <option value="">None</option>
        <optgroup v-if="categories.length" label="Categories">
          <option v-for="c in categories" :key="c.id" :value="`c:${c.id}`">{{ c.name }}</option>
        </optgroup>
        <optgroup v-if="people.length > 1" label="Individual budgets">
          <option v-for="p in people" :key="p.uid" :value="`m:${p.uid}`">{{ p.name }}</option>
        </optgroup>
      </select>
    </div>

    <template v-if="people.length > 1">
      <div>
        <label class="label" for="split-paid-by">Paid by</label>
        <select id="split-paid-by" :value="split.paidByUID ?? ''" class="input" @change="setPaidBy(($event.target as HTMLSelectElement).value)">
          <option value="">Not tracked</option>
          <option v-for="p in people" :key="p.uid" :value="p.uid">{{ p.name }}</option>
        </select>
      </div>

      <div v-if="split.paidByUID">
        <div class="flex items-center justify-between">
          <span class="label mb-0">Split between</span>
          <div class="flex rounded-lg bg-card-surface p-0.5 text-xs font-semibold">
            <button type="button" class="rounded-md px-2.5 py-1" :class="!isCustom ? 'bg-white shadow-sm' : 'text-zinc-500'" @click="setCustom(false)">Equally</button>
            <button type="button" class="rounded-md px-2.5 py-1" :class="isCustom ? 'bg-white shadow-sm' : 'text-zinc-500'" @click="setCustom(true)">By amount</button>
          </div>
        </div>
        <ul class="mt-2 divide-y divide-black/5 rounded-xl border border-secondary bg-white">
          <li v-for="p in people" :key="p.uid" class="flex items-center gap-3 px-3 py-2">
            <label class="flex min-w-0 flex-1 items-center gap-2.5">
              <input type="checkbox" class="size-4 accent-trip-500" :checked="split.splitUIDs.includes(p.uid)" @change="toggle(p.uid)" />
              <span class="truncate text-sm">{{ p.name }}</span>
            </label>
            <input
              v-if="isCustom && split.splitUIDs.includes(p.uid)"
              :value="split.splitAmounts[p.uid] ?? 0"
              type="number" min="0" step="any" inputmode="decimal"
              class="input w-28 py-1 text-right"
              :aria-label="`${p.name}'s share`"
              @input="setAmount(p.uid, ($event.target as HTMLInputElement).value)"
            />
            <span v-else-if="split.splitUIDs.includes(p.uid) && total > 0" class="text-xs text-zinc-500">
              {{ formatMoney(total / split.splitUIDs.length, currency) }}
            </span>
          </li>
        </ul>
        <p v-if="isCustom" class="mt-1.5 text-xs" :class="Math.abs(customTotal - total) > 0.01 ? 'text-danger' : 'text-zinc-500'">
          {{ formatMoney(customTotal, currency) }} of {{ formatMoney(total, currency) }}
          <template v-if="Math.abs(customTotal - total) > 0.01"> · Amounts don’t add up to the total yet.</template>
        </p>
      </div>
    </template>
  </div>
</template>
