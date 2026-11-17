<script setup lang="ts">
import { computed, ref } from 'vue'
import { PhCoins } from '@phosphor-icons/vue'
import type { CostSplit } from '@/lib/model'
import { activityCost, expenseCost, itemShares, stayCost, transportCost, type Converted } from '@/lib/money'
import { formatMoney } from '@/lib/dates'
import { useTripContext } from '@/composables/tripContext'

/**
 * Who chips in for what (web only for now): every costed activity, stay, ride and
 * expense, with each person's share of it and who paid.
 */
const { trip, content, people } = useTripContext()
const { activities, stays, transport, expenses } = content

type Kind = 'activities' | 'stays' | 'transport' | 'expenses'
const kinds: { id: Kind; label: string }[] = [
  { id: 'activities', label: 'Activities' },
  { id: 'stays', label: 'Stays' },
  { id: 'transport', label: 'Transport' },
  { id: 'expenses', label: 'Other' },
]
const kind = ref<Kind>('activities')

interface Row {
  id: string
  title: string
  total: number
  paidBy: string | null
  shares: Record<string, number>
  noRate: boolean
}

const uids = computed(() => people.value.map((p) => p.uid))

function row(id: string, title: string, split: CostSplit, converted: Converted | null): Row {
  return {
    id,
    title,
    total: converted?.cost ?? 0,
    paidBy: split.paidByUID,
    shares: converted ? itemShares(split, converted, uids.value) : {},
    noRate: !converted,
  }
}

const rows = computed<Row[]>(() => {
  const tc = trip.value.currency
  switch (kind.value) {
    case 'activities':
      return activities.value.filter((a) => (a.cost ?? 0) > 0).sort((a, b) => a.date.getTime() - b.date.getTime()).map((a) => row(a.id, a.title, a, activityCost(a, tc)))
    case 'stays':
      return stays.value.filter((s) => s.totalCost > 0).sort((a, b) => a.startDate.getTime() - b.startDate.getTime()).map((s) => row(s.id, s.name, s, stayCost(s)))
    case 'transport':
      return transport.value.filter((t) => t.cost > 0).sort((a, b) => a.departureDate.getTime() - b.departureDate.getTime()).map((t) => row(t.id, `${t.departureLocation} → ${t.arrivalLocation}`, t, transportCost(t, tc)))
    default:
      return expenses.value.filter((e) => e.cost > 0).sort((a, b) => (a.date?.getTime() ?? 0) - (b.date?.getTime() ?? 0)).map((e) => row(e.id, e.name, e, expenseCost(e, tc)))
  }
})

const totals = computed(() => {
  const byPerson: Record<string, number> = {}
  let all = 0
  for (const r of rows.value) {
    all += r.total
    for (const [uid, amount] of Object.entries(r.shares)) byPerson[uid] = (byPerson[uid] ?? 0) + amount
  }
  return { byPerson, all }
})

const money = (amount: number) => formatMoney(amount, trip.value.currency)
</script>

<template>
  <section>
    <div class="mb-2 flex flex-wrap items-center justify-between gap-2">
      <h2 class="tracked-label flex items-center gap-1.5"><PhCoins class="size-3.5" /> Who chips in for what</h2>
      <div class="flex rounded-xl bg-card-surface p-1 text-sm font-medium">
        <button
          v-for="k in kinds" :key="k.id"
          class="rounded-lg px-3 py-1"
          :class="kind === k.id ? 'bg-white shadow-sm' : 'text-zinc-500'"
          @click="kind = k.id"
        >{{ k.label }}</button>
      </div>
    </div>

    <p v-if="!rows.length" class="sticker-card-trip p-4 text-sm text-zinc-500">No {{ kinds.find((k) => k.id === kind)?.label.toLowerCase() }} with a cost yet.</p>
    <div v-else class="sticker-card-trip overflow-x-auto">
      <table class="w-full min-w-max text-sm">
        <thead>
          <tr class="border-b border-trip-border text-left">
            <th class="sticky left-0 bg-white px-4 py-2.5 font-semibold">Item</th>
            <th class="px-3 py-2.5 text-right font-semibold">Total</th>
            <th v-for="p in people" :key="p.uid" class="px-3 py-2.5 text-right font-semibold whitespace-nowrap">{{ p.name }}</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-trip-border">
          <tr v-for="r in rows" :key="r.id">
            <td class="sticky left-0 max-w-56 truncate bg-white px-4 py-2.5 font-medium" :title="r.title">{{ r.title }}</td>
            <td class="px-3 py-2.5 text-right whitespace-nowrap">
              <span v-if="r.noRate" class="text-xs text-zinc-400">No rate</span>
              <template v-else>{{ money(r.total) }}</template>
            </td>
            <td v-for="p in people" :key="p.uid" class="px-3 py-2.5 text-right whitespace-nowrap">
              <span :class="r.shares[p.uid] ? '' : 'text-zinc-300'">{{ r.shares[p.uid] ? money(r.shares[p.uid] ?? 0) : '–' }}</span>
              <span v-if="r.paidBy === p.uid" class="ml-1 rounded-pill bg-mint px-1 py-0.5 text-[10px] font-bold text-mint-text uppercase" title="Paid for this">Paid</span>
            </td>
          </tr>
        </tbody>
        <tfoot>
          <tr class="border-t-2 border-trip-border font-semibold">
            <td class="sticky left-0 bg-white px-4 py-2.5">Total</td>
            <td class="px-3 py-2.5 text-right whitespace-nowrap">{{ money(totals.all) }}</td>
            <td v-for="p in people" :key="p.uid" class="px-3 py-2.5 text-right whitespace-nowrap">{{ money(totals.byPerson[p.uid] ?? 0) }}</td>
          </tr>
        </tfoot>
      </table>
    </div>
    <p class="mt-2 text-xs text-zinc-500">Shares follow each cost’s split; a cost with no split is shared evenly by everyone. “Paid” marks who paid for it.</p>
  </section>
</template>
