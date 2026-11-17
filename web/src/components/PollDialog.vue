<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { PhPlus, PhX } from '@phosphor-icons/vue'
import AppDialog from './AppDialog.vue'
import { combine, fromDateInput, toDateInput } from '@/lib/dates'
import { createPoll } from '@/lib/writes'
import { useTripContext } from '@/composables/tripContext'

/** PollEditSheet: a question with options, or a proposed activity the group votes Yes/No on. */
const open = defineModel<boolean>('open', { required: true })
const { trip, uid } = useTripContext()

const kind = ref<'question' | 'activityProposal'>('question')
const question = ref('')
const options = ref<string[]>(['', ''])
const location = ref('')
const dayInput = ref('')
const time = ref('09:00')
const saving = ref(false)
const error = ref<string | null>(null)

watch(open, (isOpen) => {
  if (!isOpen) return
  kind.value = 'question'
  question.value = ''
  options.value = ['', '']
  location.value = ''
  dayInput.value = toDateInput(trip.value.startDate)
  time.value = '09:00'
  error.value = null
})

const trimmed = computed(() => options.value.map((o) => o.trim()).filter(Boolean))
const valid = computed(() => question.value.trim() && (kind.value === 'activityProposal' || trimmed.value.length >= 2))

async function save() {
  if (!valid.value) return
  saving.value = true
  try {
    await createPoll(trip.value.id, uid.value, {
      kind: kind.value,
      question: question.value.trim(),
      options: trimmed.value,
      location: location.value.trim(),
      proposedDate: dayInput.value ? combine(fromDateInput(dayInput.value), time.value) : null,
      iconName: 'mappin.and.ellipse',
    })
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
  <AppDialog v-model:open="open" :title="kind === 'question' ? 'New poll' : 'Propose activity'" :theme="trip.theme">
    <form id="poll-form" class="space-y-4" @submit.prevent="save">
      <div class="flex rounded-xl bg-card-surface p-1 text-sm font-medium">
        <button type="button" class="flex-1 rounded-lg px-3 py-1.5" :class="kind === 'question' ? 'bg-white shadow-sm' : 'text-zinc-500'" @click="kind = 'question'">Question</button>
        <button type="button" class="flex-1 rounded-lg px-3 py-1.5" :class="kind === 'activityProposal' ? 'bg-white shadow-sm' : 'text-zinc-500'" @click="kind = 'activityProposal'">Activity</button>
      </div>
      <div>
        <label class="label" for="poll-question">{{ kind === 'question' ? 'Question' : 'Activity' }}</label>
        <input id="poll-question" v-model="question" class="input" :placeholder="kind === 'question' ? 'Which beach on day 2?' : 'Island hopping tour'" required />
      </div>
      <template v-if="kind === 'question'">
        <div>
          <span class="label">Options</span>
          <div class="space-y-2">
            <div v-for="(_, i) in options" :key="i" class="flex gap-2">
              <input v-model="options[i]" class="input" :placeholder="`Option ${i + 1}`" :aria-label="`Option ${i + 1}`" />
              <button v-if="options.length > 2" type="button" class="icon-btn shrink-0" aria-label="Remove option" @click="options.splice(i, 1)"><PhX class="size-4" /></button>
            </div>
          </div>
          <button type="button" class="btn-ghost mt-2 px-2 py-1 text-sm" @click="options.push('')"><PhPlus class="size-4" /> Add option</button>
        </div>
      </template>
      <template v-else>
        <div>
          <label class="label" for="poll-location">Where</label>
          <input id="poll-location" v-model="location" class="input" placeholder="Optional" />
        </div>
        <div class="grid grid-cols-[1fr_auto] gap-3">
          <div>
            <label class="label" for="poll-day">Day</label>
            <input id="poll-day" v-model="dayInput" type="date" class="input" :min="toDateInput(trip.startDate)" :max="toDateInput(trip.endDate)" />
          </div>
          <div>
            <label class="label" for="poll-time">Time</label>
            <input id="poll-time" v-model="time" type="time" class="input" />
          </div>
        </div>
        <p class="text-xs text-zinc-500">The group votes Yes or No. If the owner approves it, it goes on the itinerary.</p>
      </template>
      <p v-if="error" class="text-sm text-danger">{{ error }}</p>
    </form>
    <template #footer>
      <button type="submit" form="poll-form" class="btn-primary ml-auto" :disabled="!valid || saving">{{ saving ? 'Saving…' : 'Start vote' }}</button>
    </template>
  </AppDialog>
</template>
