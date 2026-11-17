<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { PhCheck, PhTrash } from '@phosphor-icons/vue'
import AppDialog from './AppDialog.vue'
import UnlockNote from './UnlockNote.vue'
import { tripThemes, type Trip, type TripTheme } from '@/lib/model'
import { fromDateInput, toDateInput } from '@/lib/dates'
import { createTrip, deleteTrip, freeTripLimit, updateTrip } from '@/lib/writes'
import { useAuthStore } from '@/stores/auth'
import { useTripsStore } from '@/stores/trips'

/** New trip (trip: undefined) or edit an existing one's details. */
const props = defineProps<{ trip?: Trip }>()
const open = defineModel<boolean>('open', { required: true })

const authStore = useAuthStore()
const tripsStore = useTripsStore()
const router = useRouter()

const name = ref('')
const location = ref('')
const start = ref('')
const end = ref('')
const theme = ref<TripTheme>('teal')
const currency = ref('PHP')
const description = ref('')
const saving = ref(false)
const error = ref<string | null>(null)

/** Only the account that created a trip can delete it (TripSettingsView). */
const canDelete = computed(() => !!props.trip && props.trip.ownerUID === authStore.user?.uid)
async function remove() {
  const trip = props.trip
  const uid = authStore.user?.uid
  if (!trip || !uid) return
  if (!window.confirm(`Delete “${trip.name}”? This deletes it for everyone on the trip and can’t be undone.`)) return
  saving.value = true
  error.value = null
  try {
    await deleteTrip(trip.id, uid)
    open.value = false
    await router.replace({ name: 'trips' })
  } catch (err) {
    console.error(err)
    error.value = 'Couldn’t delete the trip. Check your connection and try again.'
  } finally {
    saving.value = false
  }
}

const currencies = ['PHP', 'USD', 'SGD', 'JPY', 'KRW', 'THB', 'VND', 'MYR', 'IDR', 'HKD', 'TWD', 'CNY', 'EUR', 'GBP', 'AUD', 'CAD']

watch(open, (isOpen) => {
  if (!isOpen) return
  const trip = props.trip
  const today = new Date()
  name.value = trip?.name ?? ''
  location.value = trip?.location ?? ''
  start.value = toDateInput(trip?.startDate ?? today)
  end.value = toDateInput(trip?.endDate ?? today)
  theme.value = trip?.theme ?? 'teal'
  currency.value = trip?.currency ?? 'PHP'
  description.value = trip?.tripDescription ?? ''
  error.value = null
})

const isNew = computed(() => !props.trip)
const blocked = computed(() => isNew.value && !tripsStore.canCreateTrip)
const valid = computed(() => name.value.trim() && location.value.trim() && start.value && end.value && end.value >= start.value)

async function save() {
  const uid = authStore.user?.uid
  if (!uid || !valid.value || blocked.value) return
  saving.value = true
  error.value = null
  const input = {
    name: name.value.trim(),
    location: location.value.trim(),
    theme: theme.value,
    startDate: fromDateInput(start.value),
    endDate: fromDateInput(end.value),
    currency: currency.value,
    tripDescription: description.value.trim(),
  }
  try {
    if (props.trip) {
      await updateTrip(props.trip.id, input, input.location !== props.trip.location)
      open.value = false
    } else {
      const id = await createTrip(uid, input, tripsStore.isUnlocked)
      open.value = false
      await router.push({ name: 'trip', params: { id } })
    }
  } catch (err) {
    console.error(err)
    error.value = 'Couldn’t save the trip. Check your connection and try again.'
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <AppDialog v-model:open="open" :title="isNew ? 'New trip' : 'Trip details'" :theme="theme">
    <UnlockNote v-if="blocked" :reason="`Free includes ${freeTripLimit} trips. Unlock for unlimited trips.`" />
    <form v-else id="trip-form" class="space-y-4" @submit.prevent="save">
      <div>
        <label class="label" for="trip-name">Trip name</label>
        <input id="trip-name" v-model="name" class="input" placeholder="Baguio with friends" required />
      </div>
      <div>
        <label class="label" for="trip-location">Where</label>
        <input id="trip-location" v-model="location" class="input" placeholder="Baguio, Philippines" required />
      </div>
      <div class="grid grid-cols-2 gap-3">
        <div>
          <label class="label" for="trip-start">Start</label>
          <input id="trip-start" v-model="start" type="date" class="input" required />
        </div>
        <div>
          <label class="label" for="trip-end">End</label>
          <input id="trip-end" v-model="end" type="date" :min="start" class="input" required />
        </div>
      </div>
      <div>
        <span class="label">Color</span>
        <div class="flex flex-wrap gap-2">
          <button
            v-for="option in tripThemes"
            :key="option"
            type="button"
            :data-theme="option"
            class="flex size-9 items-center justify-center rounded-full bg-trip-500 ring-offset-2 ring-offset-canvas transition"
            :class="theme === option ? 'ring-2 ring-ink' : ''"
            :aria-label="option"
            :aria-pressed="theme === option"
            @click="theme = option"
          >
            <PhCheck v-if="theme === option" class="size-4 text-white" />
          </button>
        </div>
      </div>
      <div>
        <label class="label" for="trip-currency">Currency</label>
        <select id="trip-currency" v-model="currency" class="input">
          <option v-if="!currencies.includes(currency)" :value="currency">{{ currency }}</option>
          <option v-for="code in currencies" :key="code" :value="code">{{ code }}</option>
        </select>
      </div>
      <div>
        <label class="label" for="trip-description">Notes</label>
        <textarea id="trip-description" v-model="description" rows="3" class="input" placeholder="Optional" />
      </div>
      <p v-if="error" class="text-sm text-danger">{{ error }}</p>
    </form>
    <template v-if="!blocked" #footer>
      <button v-if="canDelete" type="button" class="btn-danger" :disabled="saving" @click="remove"><PhTrash class="size-4" /> Delete trip</button>
      <button v-else type="button" class="btn-ghost" @click="open = false">Cancel</button>
      <button type="submit" form="trip-form" class="btn-primary ml-auto" :disabled="!valid || saving">
        {{ saving ? 'Saving…' : isNew ? 'Create trip' : 'Save' }}
      </button>
    </template>
  </AppDialog>
</template>
