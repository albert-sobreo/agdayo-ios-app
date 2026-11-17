<script setup lang="ts">
import { computed, ref } from 'vue'
import { PhAirplane, PhBed, PhChartBar, PhLock, PhMapTrifold, PhPlus, PhShoppingCart, PhTag, PhUser } from '@phosphor-icons/vue'
import BudgetCategoryDialog from '../BudgetCategoryDialog.vue'
import ExpenseDialog from '../ExpenseDialog.vue'
import MemberBudgetDialog from '../MemberBudgetDialog.vue'
import MemberContributions from '../MemberContributions.vue'
import UnlockNote from '../UnlockNote.vue'
import type { Activity, BudgetCategory, CostSplit, Expense, Stay, Transport } from '@/lib/model'
import { activityCost, expenseCost, memberBreakdown, spentBreakdown, transportCost } from '@/lib/money'
import { formatMoney, formatShort } from '@/lib/dates'
import { useTripContext } from '@/composables/tripContext'

/** The Budget screen (BudgetOverviewView): planned vs spent, categories, individual budgets, every cost. */
const emit = defineEmits<{ activity: [Activity]; stay: [Stay]; transport: [Transport] }>()
const { trip, content, people, name, isUnlocked } = useTripContext()
const { activities, stays, transport, expenses, budgetCategories } = content

const costs = computed(() => ({ activities: activities.value, stays: stays.value, transport: transport.value, expenses: expenses.value }))
const spent = computed(() => spentBreakdown(costs.value, trip.value.currency))
const budget = computed(() => trip.value.overallBudget)
const over = computed(() => budget.value > 0 && spent.value.total > budget.value)
const fraction = computed(() => (budget.value > 0 ? Math.min(spent.value.total / budget.value, 1) : 0))

/** Each person's share by kind, against their individual budget. */
const perMember = computed(() => memberBreakdown(costs.value, trip.value.currency, people.value.map((p) => p.uid)))
const memberRows = (uid: string) => {
  const m = perMember.value[uid]
  return [
    { icon: PhMapTrifold, title: 'Activities', amount: m?.activities ?? 0 },
    { icon: PhBed, title: 'Stays', amount: m?.stays ?? 0 },
    { icon: PhAirplane, title: 'Transport', amount: m?.transport ?? 0 },
    { icon: PhShoppingCart, title: 'Other', amount: m?.expenses ?? 0 },
  ]
}

const spentFor = (include: (item: CostSplit) => boolean) => spentBreakdown(costs.value, trip.value.currency, include).total
const sortedCategories = computed(() => [...budgetCategories.value].sort((a, b) => a.name.localeCompare(b.name)))

function attachment(item: CostSplit): string | null {
  if (item.budgetCategoryID) return budgetCategories.value.find((c) => c.id === item.budgetCategoryID)?.name ?? null
  if (item.budgetMemberUID) return name(item.budgetMemberUID)
  return null
}

const costedActivities = computed(() => activities.value.filter((a) => a.cost !== null).sort((a, b) => a.date.getTime() - b.date.getTime()))
const costedStays = computed(() => stays.value.filter((s) => s.totalCost > 0).sort((a, b) => a.startDate.getTime() - b.startDate.getTime()))
const costedTransport = computed(() => transport.value.filter((t) => t.cost > 0).sort((a, b) => a.departureDate.getTime() - b.departureDate.getTime()))
const sortedExpenses = computed(() => [...expenses.value].sort((a, b) => (b.date?.getTime() ?? 0) - (a.date?.getTime() ?? 0)))

/** "≈ ₱1,234" under a cost in another currency, or a note that it has no rate. */
function converted(currency: string | null, value: { cost: number } | null): string | null {
  if (!currency || currency === trip.value.currency) return null
  return value ? `≈ ${formatMoney(value.cost, trip.value.currency)}` : 'No exchange rate'
}

const breakdown = computed(() => [
  { icon: PhMapTrifold, title: 'Activities', amount: spent.value.activities },
  { icon: PhBed, title: 'Stays', amount: spent.value.stays },
  { icon: PhAirplane, title: 'Transport', amount: spent.value.transport },
  { icon: PhShoppingCart, title: 'Other', amount: spent.value.expenses },
])

const categoryDialog = ref<{ open: boolean; category?: BudgetCategory }>({ open: false })
const expenseDialog = ref<{ open: boolean; expense?: Expense }>({ open: false })
const memberDialog = ref<{ open: boolean; uid: string | null }>({ open: false, uid: null })
const showReportLock = ref(false)
</script>

<template>
  <div class="grid grid-cols-1 gap-6 xl:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
    <div class="space-y-6">
      <!-- Hero -->
      <section class="rounded-card bg-blush p-5 sm:p-6">
        <p class="tracked-label text-maroon/70">Spent so far</p>
        <p class="mt-1 font-display text-5xl font-semibold text-maroon sm:text-6xl">{{ formatMoney(spent.total, trip.currency) }}</p>
        <template v-if="budget > 0">
          <div class="mt-4 h-2 overflow-hidden rounded-full bg-rose-track">
            <div class="h-full rounded-full bg-brand-rose transition-all" :style="{ width: `${fraction * 100}%` }" />
          </div>
          <div class="mt-2 flex justify-between text-sm text-maroon/85">
            <span>of {{ formatMoney(budget, trip.currency) }}</span>
            <span class="font-semibold">{{ over ? `${formatMoney(spent.total - budget, trip.currency)} over` : `${formatMoney(budget - spent.total, trip.currency)} left` }}</span>
          </div>
        </template>
        <p v-else class="mt-2 text-sm text-maroon/85">Add budget categories to set a budget for this trip.</p>
      </section>

      <!-- Daily report: part of the full unlock -->
      <button v-if="!isUnlocked" class="sticker-card-trip flex w-full items-center gap-3 p-4 text-left" @click="showReportLock = !showReportLock">
        <PhChartBar class="size-6 text-trip-500" />
        <span class="min-w-0 flex-1">
          <span class="block font-semibold">Daily report</span>
          <span class="block text-sm text-zinc-500">Spending day by day</span>
        </span>
        <PhLock class="size-4 text-zinc-400" />
      </button>
      <UnlockNote v-if="showReportLock && !isUnlocked" reason="The daily budget report is part of the full unlock." />

      <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <div v-for="tile in breakdown" :key="tile.title" class="sticker-card-trip p-3">
          <component :is="tile.icon" class="size-5 text-trip-500" />
          <p class="mt-2 text-xs text-zinc-500">{{ tile.title }}</p>
          <p class="font-display text-xl font-semibold">{{ formatMoney(tile.amount, trip.currency) }}</p>
        </div>
      </div>

      <!-- Categories -->
      <section>
        <div class="mb-2 flex items-center justify-between">
          <h2 class="tracked-label flex items-center gap-1.5"><PhTag class="size-3.5" /> Categories</h2>
          <button class="btn-ghost px-2 py-1 text-sm" @click="categoryDialog = { open: true }"><PhPlus class="size-4" /> Category</button>
        </div>
        <p v-if="!sortedCategories.length" class="sticker-card-trip p-4 text-sm text-zinc-500">No budget categories yet. Add one to start planning your spending.</p>
        <ul v-else class="space-y-2">
          <li v-for="c in sortedCategories" :key="c.id">
            <button class="sticker-card-trip block w-full p-4 text-left transition hover:bg-trip-50" @click="categoryDialog = { open: true, category: c }">
              <div class="flex items-baseline justify-between gap-2">
                <span class="truncate font-semibold">{{ c.name }}</span>
                <span class="shrink-0 text-sm text-zinc-600">{{ formatMoney(spentFor((i) => i.budgetCategoryID === c.id), trip.currency) }} / {{ formatMoney(c.amount, trip.currency) }}</span>
              </div>
              <div class="mt-2 h-1.5 overflow-hidden rounded-full bg-trip-100">
                <div
                  class="h-full rounded-full"
                  :class="spentFor((i) => i.budgetCategoryID === c.id) > c.amount ? 'bg-danger' : 'bg-trip-500'"
                  :style="{ width: `${c.amount > 0 ? Math.min(spentFor((i) => i.budgetCategoryID === c.id) / c.amount, 1) * 100 : 0}%` }"
                />
              </div>
            </button>
          </li>
        </ul>
      </section>

      <!-- Per person: their share of every cost, by kind, against their own budget -->
      <section v-if="people.length > 1">
        <h2 class="tracked-label mb-2 flex items-center gap-1.5"><PhUser class="size-3.5" /> Per person</h2>
        <ul class="space-y-2">
          <li v-for="p in people" :key="p.uid" class="sticker-card-trip p-4">
            <div class="flex items-baseline justify-between gap-2">
              <span class="truncate font-semibold">{{ p.name }}</span>
              <button class="shrink-0 text-sm text-zinc-600 hover:text-ink" :aria-label="`Set ${p.name}'s budget`" @click="memberDialog = { open: true, uid: p.uid }">
                <span class="font-semibold text-ink">{{ formatMoney(perMember[p.uid]?.total ?? 0, trip.currency) }}</span>
                <template v-if="trip.memberBudgets[p.uid]"> / {{ formatMoney(trip.memberBudgets[p.uid] ?? 0, trip.currency) }}</template>
                <template v-else> · <span class="underline">Set budget</span></template>
              </button>
            </div>
            <div v-if="trip.memberBudgets[p.uid]" class="mt-2 h-1.5 overflow-hidden rounded-full bg-trip-100">
              <div
                class="h-full rounded-full"
                :class="(perMember[p.uid]?.total ?? 0) > (trip.memberBudgets[p.uid] ?? 0) ? 'bg-danger' : 'bg-trip-500'"
                :style="{ width: `${Math.min((perMember[p.uid]?.total ?? 0) / (trip.memberBudgets[p.uid] ?? 1), 1) * 100}%` }"
              />
            </div>
            <dl class="mt-3 grid grid-cols-2 gap-x-4 gap-y-1.5 text-sm sm:grid-cols-4">
              <div v-for="row in memberRows(p.uid)" :key="row.title" class="flex items-center gap-1.5 sm:block">
                <dt class="flex items-center gap-1 text-xs text-zinc-500"><component :is="row.icon" class="size-3.5 text-trip-500" /> {{ row.title }}</dt>
                <dd class="ml-auto font-medium sm:ml-0">{{ formatMoney(row.amount, trip.currency) }}</dd>
              </div>
            </dl>
            <p class="mt-2 text-xs text-zinc-500">
              Paid {{ formatMoney(perMember[p.uid]?.paid ?? 0, trip.currency) }}
              <template v-if="spentFor((i) => i.budgetMemberUID === p.uid) > 0"> · {{ formatMoney(spentFor((i) => i.budgetMemberUID === p.uid), trip.currency) }} tagged to their budget</template>
            </p>
          </li>
        </ul>
        <p class="mt-2 text-xs text-zinc-500">A person’s share follows each cost’s split. Costs with no split are shared evenly by everyone on the trip.</p>
      </section>
    </div>

    <!-- Every cost -->
    <div class="space-y-6">
      <section>
        <div class="mb-2 flex items-center justify-between">
          <h2 class="tracked-label flex items-center gap-1.5"><PhShoppingCart class="size-3.5" /> Other expenses</h2>
          <button class="btn-ghost px-2 py-1 text-sm" @click="expenseDialog = { open: true }"><PhPlus class="size-4" /> Expense</button>
        </div>
        <p v-if="!sortedExpenses.length" class="sticker-card-trip p-4 text-sm text-zinc-500">Snacks, souvenirs, tips: anything that isn’t an activity, stay or ride.</p>
        <ul v-else class="sticker-card-trip divide-y divide-trip-border">
          <li v-for="e in sortedExpenses" :key="e.id">
            <button class="flex w-full items-center gap-3 px-4 py-3 text-left transition hover:bg-trip-50" @click="expenseDialog = { open: true, expense: e }">
              <span class="min-w-0 flex-1">
                <span class="block truncate font-medium">{{ e.name }}</span>
                <span class="block text-xs text-zinc-500">{{ [e.date ? formatShort(e.date) : null, attachment(e), e.paidByUID ? `Paid by ${name(e.paidByUID)}` : null].filter(Boolean).join(' · ') }}</span>
              </span>
              <span class="text-right">
                <span class="block font-semibold">{{ formatMoney(e.cost, e.costCurrency ?? trip.currency) }}</span>
                <span v-if="converted(e.costCurrency, expenseCost(e, trip.currency))" class="block text-xs text-zinc-500">{{ converted(e.costCurrency, expenseCost(e, trip.currency)) }}</span>
              </span>
            </button>
          </li>
        </ul>
      </section>

      <section v-if="costedActivities.length">
        <h2 class="tracked-label mb-2 flex items-center gap-1.5"><PhMapTrifold class="size-3.5" /> Activities</h2>
        <ul class="sticker-card-trip divide-y divide-trip-border">
          <li v-for="a in costedActivities" :key="a.id">
            <button class="flex w-full items-center gap-3 px-4 py-3 text-left transition hover:bg-trip-50" @click="emit('activity', a)">
              <span class="min-w-0 flex-1">
                <span class="block truncate font-medium">{{ a.title }}</span>
                <span class="block text-xs text-zinc-500">{{ [formatShort(a.date), attachment(a)].filter(Boolean).join(' · ') }}</span>
              </span>
              <span class="text-right">
                <span class="block font-semibold">{{ formatMoney(a.cost ?? 0, a.costCurrency ?? trip.currency) }}</span>
                <span v-if="converted(a.costCurrency, activityCost(a, trip.currency))" class="block text-xs text-zinc-500">{{ converted(a.costCurrency, activityCost(a, trip.currency)) }}</span>
              </span>
            </button>
          </li>
        </ul>
      </section>

      <section v-if="costedStays.length">
        <h2 class="tracked-label mb-2 flex items-center gap-1.5"><PhBed class="size-3.5" /> Stays</h2>
        <ul class="sticker-card-trip divide-y divide-trip-border">
          <li v-for="s in costedStays" :key="s.id">
            <button class="flex w-full items-center gap-3 px-4 py-3 text-left transition hover:bg-trip-50" @click="emit('stay', s)">
              <span class="min-w-0 flex-1">
                <span class="block truncate font-medium">{{ s.name }}</span>
                <span class="block text-xs text-zinc-500">{{ [`${formatShort(s.startDate)} – ${formatShort(s.endDate)}`, attachment(s)].filter(Boolean).join(' · ') }}</span>
              </span>
              <span class="font-semibold">{{ formatMoney(s.totalCost, trip.currency) }}</span>
            </button>
          </li>
        </ul>
      </section>

      <section v-if="costedTransport.length">
        <h2 class="tracked-label mb-2 flex items-center gap-1.5"><PhAirplane class="size-3.5" /> Transport</h2>
        <ul class="sticker-card-trip divide-y divide-trip-border">
          <li v-for="t in costedTransport" :key="t.id">
            <button class="flex w-full items-center gap-3 px-4 py-3 text-left transition hover:bg-trip-50" @click="emit('transport', t)">
              <span class="min-w-0 flex-1">
                <span class="block truncate font-medium">{{ t.departureLocation }} → {{ t.arrivalLocation }}</span>
                <span class="block text-xs text-zinc-500">{{ [formatShort(t.departureDate), attachment(t)].filter(Boolean).join(' · ') }}</span>
              </span>
              <span class="text-right">
                <span class="block font-semibold">{{ formatMoney(t.cost, t.currency) }}</span>
                <span v-if="converted(t.currency, transportCost(t, trip.currency))" class="block text-xs text-zinc-500">{{ converted(t.currency, transportCost(t, trip.currency)) }}</span>
              </span>
            </button>
          </li>
        </ul>
      </section>
    </div>

    <MemberContributions v-if="people.length > 1" class="xl:col-span-2" />

    <BudgetCategoryDialog v-model:open="categoryDialog.open" :category="categoryDialog.category" />
    <ExpenseDialog v-model:open="expenseDialog.open" :expense="expenseDialog.expense" />
    <MemberBudgetDialog v-model:open="memberDialog.open" :uid="memberDialog.uid" />
  </div>
</template>
