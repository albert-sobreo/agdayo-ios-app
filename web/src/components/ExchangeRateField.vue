<script setup lang="ts">
import { ref, watch } from 'vue'
import { PhArrowsClockwise } from '@phosphor-icons/vue'
import { fetchRate } from '@/lib/money'
import { formatMoney } from '@/lib/dates'

/**
 * The rate from a cost's currency to the trip's (ExchangeRateField in the app).
 * Filled in from today's rate when empty, and saved with the cost so totals don't drift.
 */
const props = defineProps<{ from: string; to: string; amount: number }>()
const rate = defineModel<number | null>({ required: true })
const loading = ref(false)
const failed = ref(false)

async function load() {
  loading.value = true
  failed.value = false
  const value = await fetchRate(props.from, props.to)
  loading.value = false
  if (value === null) failed.value = true
  else rate.value = Math.round(value * 1e6) / 1e6
}

watch(
  () => [props.from, props.to] as const,
  ([from, to]) => {
    if (from !== to && rate.value === null) void load()
  },
  { immediate: true },
)
</script>

<template>
  <div v-if="from !== to">
    <label class="label" for="exchange-rate">1 {{ from }} = ? {{ to }}</label>
    <div class="flex gap-2">
      <input
        id="exchange-rate"
        :value="rate ?? ''"
        type="number" min="0" step="any" inputmode="decimal"
        class="input"
        placeholder="Exchange rate"
        @input="rate = Number(($event.target as HTMLInputElement).value) || null"
      />
      <button type="button" class="btn-secondary shrink-0 px-3" :disabled="loading" aria-label="Use today's rate" @click="load">
        <PhArrowsClockwise class="size-4" :class="loading && 'animate-spin'" />
      </button>
    </div>
    <p class="mt-1 text-xs" :class="failed ? 'text-danger' : 'text-zinc-500'">
      <template v-if="failed">Couldn’t get today’s rate. Type it in.</template>
      <template v-else-if="rate">≈ {{ formatMoney(amount * rate, to) }}</template>
    </p>
  </div>
</template>
