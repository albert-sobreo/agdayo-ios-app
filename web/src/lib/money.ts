import type { Activity, CostSplit, Expense, Settlement, Stay, Transport } from './model'

/**
 * Budget and settle-up math, ported from the app (ExpenseBalanceService.swift,
 * BudgetOverviewView.swift and the models' costAndRate). Keep the two in step so
 * the web and the iPhone show the same totals and the same "who owes whom".
 */

export const currencies = ['PHP', 'USD', 'SGD', 'JPY', 'KRW', 'THB', 'VND', 'MYR', 'IDR', 'HKD', 'TWD', 'CNY', 'EUR', 'GBP', 'AUD', 'CAD']

export interface Converted {
  cost: number
  rate: number
}

/** The cost in the trip currency, or null when it's in another currency with no rate saved. */
export function inTripCurrency(cost: number | null, currency: string | null, rate: number | null, tripCurrency: string): Converted | null {
  if (cost === null) return null
  if (currency === null || currency === tripCurrency) return { cost, rate: 1 }
  if (rate === null) return null
  return { cost: cost * rate, rate }
}

export const activityCost = (a: Activity, tc: string) => inTripCurrency(a.cost, a.costCurrency, a.exchangeRateToTripCurrency, tc)
/** Stays have no currency of their own and always count as-is. */
export const stayCost = (s: Stay): Converted => ({ cost: s.totalCost, rate: 1 })
export const transportCost = (t: Transport, tc: string) => inTripCurrency(t.cost, t.currency, t.exchangeRateToTripCurrency, tc)
export const expenseCost = (e: Expense, tc: string) => inTripCurrency(e.cost, e.costCurrency, e.exchangeRateToTripCurrency, tc)

export interface TripCosts {
  activities: Activity[]
  stays: Stay[]
  transport: Transport[]
  expenses: Expense[]
}

/** Spent per kind, filtered by `include` (a budget category or a member's budget). */
export function spentBreakdown(costs: TripCosts, tripCurrency: string, include: (item: CostSplit) => boolean = () => true) {
  const sum = <T extends CostSplit>(items: T[], cost: (item: T) => Converted | null) =>
    items.filter(include).reduce((total, item) => total + (cost(item)?.cost ?? 0), 0)
  const activities = sum(costs.activities, (a) => activityCost(a, tripCurrency))
  const stays = sum(costs.stays, stayCost)
  const transport = sum(costs.transport, (t) => transportCost(t, tripCurrency))
  const expenses = sum(costs.expenses, (e) => expenseCost(e, tripCurrency))
  return { activities, stays, transport, expenses, total: activities + stays + transport + expenses }
}

/**
 * Who owes what for one item. Custom amounts win; otherwise an even split.
 * Anyone no longer on the trip is left out, and then custom amounts no longer
 * add up, so it falls back to an even split among those left.
 */
export function shares(amount: number, splitUIDs: string[], splitAmounts: Record<string, number>, rate: number, memberUIDs: Set<string>): Record<string, number> {
  let uids = splitUIDs
  let custom = splitAmounts
  if (memberUIDs.size) {
    const current = splitUIDs.filter((uid) => memberUIDs.has(uid))
    if (current.length && current.length !== splitUIDs.length) {
      uids = current
      custom = {}
    }
  }
  if (Object.keys(custom).length) return Object.fromEntries(uids.map((uid) => [uid, (custom[uid] ?? 0) * rate]))
  const even = amount / uids.length
  return Object.fromEntries(uids.map((uid) => [uid, even]))
}

/** Positive: that member is owed money. Negative: they owe. Recorded payments are netted in. */
export function balances(costs: TripCosts, settlements: Settlement[], tripCurrency: string, memberUIDs: Set<string>): Record<string, number> {
  const net: Record<string, number> = {}
  const add = (uid: string, amount: number) => (net[uid] = (net[uid] ?? 0) + amount)
  const items: { split: CostSplit; converted: Converted | null }[] = [
    ...costs.activities.map((a) => ({ split: a, converted: activityCost(a, tripCurrency) })),
    ...costs.stays.map((s) => ({ split: s, converted: stayCost(s) })),
    ...costs.transport.map((t) => ({ split: t, converted: transportCost(t, tripCurrency) })),
    ...costs.expenses.map((e) => ({ split: e, converted: expenseCost(e, tripCurrency) })),
  ]
  for (const { split, converted } of items) {
    if (!converted || converted.cost <= 0 || !split.paidByUID || !split.splitUIDs.length) continue
    add(split.paidByUID, converted.cost)
    for (const [uid, share] of Object.entries(shares(converted.cost, split.splitUIDs, split.splitAmounts, converted.rate, memberUIDs))) add(uid, -share)
  }
  for (const s of settlements) {
    add(s.fromUID, s.amount)
    add(s.toUID, -s.amount)
  }
  return net
}

export interface SuggestedPayment {
  fromUID: string
  toUID: string
  amount: number
}

/** Greedy debt simplification: the fewest payments that square everyone up. */
export function suggestedPayments(net: Record<string, number>): SuggestedPayment[] {
  const creditors = Object.entries(net).filter(([, v]) => v > 0.01).map(([uid, value]) => ({ uid, value })).sort((a, b) => b.value - a.value)
  const debtors = Object.entries(net).filter(([, v]) => v < -0.01).map(([uid, value]) => ({ uid, value: -value })).sort((a, b) => b.value - a.value)
  const result: SuggestedPayment[] = []
  let ci = 0
  let di = 0
  while (ci < creditors.length && di < debtors.length) {
    const creditor = creditors[ci]!
    const debtor = debtors[di]!
    const amount = Math.min(creditor.value, debtor.value)
    if (amount > 0.01) result.push({ fromUID: debtor.uid, toUID: creditor.uid, amount })
    creditor.value -= amount
    debtor.value -= amount
    if (creditor.value <= 0.01) ci++
    if (debtor.value <= 0.01) di++
  }
  return result
}

/** Same free service the app uses (CurrencyConversionService). */
export async function fetchRate(from: string, to: string): Promise<number | null> {
  try {
    const response = await fetch(`https://open.er-api.com/v6/latest/${encodeURIComponent(from)}`)
    if (!response.ok) return null
    const data = (await response.json()) as { rates?: Record<string, number> }
    return data.rates?.[to] ?? null
  } catch {
    return null
  }
}

/** Parses a typed amount; '' is null, anything else must be a number >= 0. */
export function parseAmount(text: string): number | null | undefined {
  if (text.trim() === '') return null
  const value = Number(text)
  return Number.isFinite(value) && value >= 0 ? value : undefined
}
