<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { PhTrash } from '@phosphor-icons/vue'
import AppDialog from './AppDialog.vue'
import type { DayNote, Trip } from '@/lib/model'
import { formatDay, startOfDay } from '@/lib/dates'
import { deleteItem, saveDayNote } from '@/lib/writes'

const props = defineProps<{ trip: Trip; note?: DayNote; day: Date }>()
const open = defineModel<boolean>('open', { required: true })

const title = ref('')
const content = ref('')
const saving = ref(false)
const error = ref<string | null>(null)

watch(open, (isOpen) => {
  if (!isOpen) return
  title.value = props.note?.title ?? ''
  content.value = props.note?.content ?? ''
  error.value = null
})

const valid = computed(() => title.value.trim() || content.value.trim())

async function save() {
  if (!valid.value) return
  saving.value = true
  try {
    await saveDayNote(props.trip.id, props.note?.id ?? null, {
      day: props.note?.day ?? startOfDay(props.day),
      title: title.value.trim(),
      content: content.value.trim(),
    })
    open.value = false
  } catch (err) {
    console.error(err)
    error.value = 'Couldn’t save. Check your connection and try again.'
  } finally {
    saving.value = false
  }
}

async function remove() {
  if (!props.note || !window.confirm('Delete this note?')) return
  saving.value = true
  try {
    await deleteItem(props.trip.id, 'dayNotes', props.note.id)
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
  <AppDialog v-model:open="open" :title="note ? 'Edit note' : 'New note'" :description="formatDay(day)" :theme="trip.theme">
    <form id="note-form" class="space-y-4" @submit.prevent="save">
      <div>
        <label class="label" for="note-title">Title</label>
        <input id="note-title" v-model="title" class="input" placeholder="Reminders" />
      </div>
      <div>
        <label class="label" for="note-content">Note</label>
        <textarea id="note-content" v-model="content" rows="6" class="input" placeholder="Bring jackets, it gets cold at night." />
      </div>
      <p v-if="error" class="text-sm text-danger">{{ error }}</p>
    </form>
    <template #footer>
      <button v-if="note" type="button" class="btn-danger" :disabled="saving" @click="remove"><PhTrash class="size-4" /> Delete</button>
      <button type="submit" form="note-form" class="btn-primary ml-auto" :disabled="!valid || saving">{{ saving ? 'Saving…' : 'Save' }}</button>
    </template>
  </AppDialog>
</template>
