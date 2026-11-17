<script setup lang="ts">
import { computed, ref } from 'vue'
import { PhArrowRight, PhCheckCircle, PhTrash } from '@phosphor-icons/vue'
import { balances, suggestedPayments, type SuggestedPayment } from '@/lib/money'
import { formatMoney, formatShort } from '@/lib/dates'
import { deleteItem, recordSettlement } from '@/lib/writes'
import { useTripContext } from '@/composables/tripContext'

/** Balances and settle-up (BalancesView): who's up or down, the fewest payments to square up, and payments made. */
const { trip, content, people, name } = useTripContext()
const { activities, stays, transport, expenses, settlements, members } = content

const memberUIDs = computed(() => new Set(members.value.map((m) => m.uid)))
const net = computed(() =>
  balances({ activities: activities.value, stays: stays.value, transport: transport.value, expenses: expenses.value }, settlements.value, trip.value.currency, memberUIDs.value),
)
const payments = computed(() => suggestedPayments(net.value))
const recorded = computed(() => [...settlements.value].sort((a, b) => b.date.getTime() - a.date.getTime()))
const busy = ref<string | null>(null)
const error = ref<string | null>(null)

async function markPaid(p: SuggestedPayment) {
  if (!window.confirm(`Mark ${formatMoney(p.amount, trip.value.currency)} from ${name(p.fromUID)} to ${name(p.toUID)} as paid?`)) return
  busy.value = `${p.fromUID}-${p.toUID}`
  error.value = null
  try {
    await recordSettlement(trip.value.id, { fromUID: p.fromUID, toUID: p.toUID, amount: Math.round(p.amount * 100) / 100 })
  } catch (err) {
    console.error(err)
    error.value = 'Couldn’t save. Check your connection and try again.'
  } finally {
    busy.value = null
  }
}

async function undo(id: string) {
  if (!window.confirm('Delete this payment? The amount goes back to owed.')) return
  busy.value = id
  try {
    await deleteItem(trip.value.id, 'settlements', id)
  } catch (err) {
    console.error(err)
    error.value = 'Couldn’t delete. Check your connection and try again.'
  } finally {
    busy.value = null
  }
}
</script>

<template>
  <div class="grid grid-cols-1 gap-6 xl:grid-cols-2">
    <div class="space-y-6">
      <section>
        <h2 class="tracked-label mb-2">Settle up</h2>
        <div v-if="!payments.length" class="flex items-center gap-3 rounded-card bg-mint p-5 text-mint-text">
          <PhCheckCircle class="size-7 shrink-0" weight="fill" />
          <p class="font-semibold">Everyone is square.</p>
        </div>
        <ul v-else class="space-y-2">
          <li v-for="p in payments" :key="`${p.fromUID}-${p.toUID}`" class="sticker-card-trip flex flex-wrap items-center gap-3 p-4">
            <span class="flex min-w-0 flex-1 items-center gap-2 font-medium">
              <span class="truncate">{{ name(p.fromUID) }}</span>
              <PhArrowRight class="size-4 shrink-0 text-trip-500" />
              <span class="truncate">{{ name(p.toUID) }}</span>
            </span>
            <span class="font-display text-2xl font-semibold">{{ formatMoney(p.amount, trip.currency) }}</span>
            <button class="btn-secondary px-3 py-1.5 text-sm" :disabled="busy !== null" @click="markPaid(p)">Mark as paid</button>
          </li>
        </ul>
        <p v-if="error" class="mt-2 text-sm text-danger">{{ error }}</p>
      </section>

      <section>
        <h2 class="tracked-label mb-2">Balances</h2>
        <ul class="sticker-card-trip divide-y divide-trip-border">
          <li v-for="p in people" :key="p.uid" class="flex items-center justify-between gap-3 px-4 py-3">
            <span class="truncate font-medium">{{ p.name }}</span>
            <span
              class="text-sm font-semibold"
              :class="(net[p.uid] ?? 0) > 0.01 ? 'text-mint-text' : (net[p.uid] ?? 0) < -0.01 ? 'text-danger' : 'text-zinc-500'"
            >
              <template v-if="(net[p.uid] ?? 0) > 0.01">gets back {{ formatMoney(net[p.uid] ?? 0, trip.currency) }}</template>
              <template v-else-if="(net[p.uid] ?? 0) < -0.01">owes {{ formatMoney(-(net[p.uid] ?? 0), trip.currency) }}</template>
              <template v-else>settled</template>
            </span>
          </li>
        </ul>
        <p class="mt-2 text-xs text-zinc-500">Counts every cost with a “Paid by” and a split: activities, stays, transport and other expenses.</p>
      </section>
    </div>

    <section>
      <h2 class="tracked-label mb-2">Payments made</h2>
      <p v-if="!recorded.length" class="sticker-card-trip p-4 text-sm text-zinc-500">Payments you mark as paid show up here.</p>
      <ul v-else class="sticker-card-trip divide-y divide-trip-border">
        <li v-for="s in recorded" :key="s.id" class="flex items-center gap-3 px-4 py-3">
          <span class="min-w-0 flex-1">
            <span class="block truncate font-medium">{{ name(s.fromUID) }} paid {{ name(s.toUID) }}</span>
            <span class="block text-xs text-zinc-500">{{ formatShort(s.date) }}</span>
          </span>
          <span class="font-semibold">{{ formatMoney(s.amount, trip.currency) }}</span>
          <button class="icon-btn size-8" aria-label="Delete payment" :disabled="busy !== null" @click="undo(s.id)"><PhTrash class="size-4" /></button>
        </li>
      </ul>
    </section>
  </div>
</template>
