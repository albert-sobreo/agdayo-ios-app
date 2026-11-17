<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { PhTrash } from '@phosphor-icons/vue'
import AppDialog from './AppDialog.vue'
import type { Idea } from '@/lib/model'
import { createIdea, deleteItem, updateIdea } from '@/lib/writes'
import { useTripContext } from '@/composables/tripContext'

/** IdeaEditSheet: a place or thing to do, with an optional note, place and link. */
const props = defineProps<{ idea?: Idea }>()
const open = defineModel<boolean>('open', { required: true })
const { trip, uid } = useTripContext()

const title = ref('')
const note = ref('')
const location = ref('')
const link = ref('')
const saving = ref(false)
const error = ref<string | null>(null)

watch(open, (isOpen) => {
  if (!isOpen) return
  title.value = props.idea?.title ?? ''
  note.value = props.idea?.note ?? ''
  location.value = props.idea?.location ?? ''
  link.value = props.idea?.link ?? ''
  error.value = null
})

const valid = computed(() => title.value.trim().length > 0)

/** Like the app: a bare "example.com" gets https:// so it opens. */
function cleanLink(value: string): string {
  const trimmed = value.trim()
  if (!trimmed) return ''
  return /^[a-z]+:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`
}

async function save() {
  if (!valid.value) return
  saving.value = true
  const input = { title: title.value.trim(), note: note.value.trim(), location: location.value.trim(), link: cleanLink(link.value) }
  try {
    if (props.idea) await updateIdea(trip.value.id, props.idea, input)
    else await createIdea(trip.value.id, uid.value, input)
    open.value = false
  } catch (err) {
    console.error(err)
    error.value = 'Couldn’t save. Check your connection and try again.'
  } finally {
    saving.value = false
  }
}

async function remove() {
  if (!props.idea || !window.confirm(`Delete “${props.idea.title}”?`)) return
  saving.value = true
  try {
    await deleteItem(trip.value.id, 'ideas', props.idea.id)
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
  <AppDialog v-model:open="open" :title="idea ? 'Edit idea' : 'New idea'" :theme="trip.theme">
    <form id="idea-form" class="space-y-4" @submit.prevent="save">
      <div>
        <label class="label" for="idea-title">Idea</label>
        <input id="idea-title" v-model="title" class="input" placeholder="Sunset at the lighthouse" required />
      </div>
      <div>
        <label class="label" for="idea-location">Where</label>
        <input id="idea-location" v-model="location" class="input" placeholder="Optional" />
      </div>
      <div>
        <label class="label" for="idea-link">Link</label>
        <input id="idea-link" v-model="link" class="input" inputmode="url" placeholder="Optional, e.g. a TikTok or blog post" />
      </div>
      <div>
        <label class="label" for="idea-note">Note</label>
        <textarea id="idea-note" v-model="note" rows="3" class="input" placeholder="Optional" />
      </div>
      <p v-if="error" class="text-sm text-danger">{{ error }}</p>
    </form>
    <template #footer>
      <button v-if="idea" type="button" class="btn-danger" :disabled="saving" @click="remove"><PhTrash class="size-4" /> Delete</button>
      <button type="submit" form="idea-form" class="btn-primary ml-auto" :disabled="!valid || saving">{{ saving ? 'Saving…' : 'Save' }}</button>
    </template>
  </AppDialog>
</template>
