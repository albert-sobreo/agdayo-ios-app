<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { PhTrash } from '@phosphor-icons/vue'
import AppDialog from './AppDialog.vue'
import { prepCategories, type PrepTask } from '@/lib/model'
import { deleteItem, savePrepTask } from '@/lib/writes'
import { useTripContext } from '@/composables/tripContext'

/** PreparationTaskEditSheet: a name, a category (one of the usual ones or your own) and notes. */
const props = defineProps<{ task?: PrepTask }>()
const open = defineModel<boolean>('open', { required: true })
const { trip } = useTripContext()

const name = ref('')
const category = ref<string>('Essentials')
const customCategory = ref('')
const notes = ref('')
const saving = ref(false)
const error = ref<string | null>(null)

watch(open, (isOpen) => {
  if (!isOpen) return
  const t = props.task
  name.value = t?.name ?? ''
  const known = t && (prepCategories as readonly string[]).includes(t.category)
  category.value = t ? (known ? t.category : 'Other') : 'Essentials'
  customCategory.value = t && !known ? t.category : ''
  notes.value = t?.notes ?? ''
  error.value = null
})

const resolvedCategory = computed(() => (category.value === 'Other' ? customCategory.value.trim() || 'Other' : category.value))
const valid = computed(() => name.value.trim().length > 0)

async function save() {
  if (!valid.value) return
  saving.value = true
  try {
    await savePrepTask(trip.value.id, props.task?.id ?? null, {
      name: name.value.trim(),
      category: resolvedCategory.value,
      notes: notes.value.trim(),
      completed: props.task?.completed ?? false,
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
  if (!props.task || !window.confirm(`Delete “${props.task.name}”?`)) return
  saving.value = true
  try {
    await deleteItem(trip.value.id, 'preparationTasks', props.task.id)
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
  <AppDialog v-model:open="open" :title="task ? 'Edit task' : 'New task'" :theme="trip.theme">
    <form id="prep-form" class="space-y-4" @submit.prevent="save">
      <div>
        <label class="label" for="prep-name">Task</label>
        <input id="prep-name" v-model="name" class="input" placeholder="Renew passport" required />
      </div>
      <div>
        <label class="label" for="prep-category">Category</label>
        <select id="prep-category" v-model="category" class="input">
          <option v-for="c in prepCategories" :key="c" :value="c">{{ c }}</option>
          <option value="Other">Other</option>
        </select>
      </div>
      <div v-if="category === 'Other'">
        <label class="label" for="prep-custom">Custom category</label>
        <input id="prep-custom" v-model="customCategory" class="input" placeholder="Optional" />
      </div>
      <div>
        <label class="label" for="prep-notes">Notes</label>
        <textarea id="prep-notes" v-model="notes" rows="3" class="input" placeholder="Optional" />
      </div>
      <p v-if="error" class="text-sm text-danger">{{ error }}</p>
    </form>
    <template #footer>
      <button v-if="task" type="button" class="btn-danger" :disabled="saving" @click="remove"><PhTrash class="size-4" /> Delete</button>
      <button type="submit" form="prep-form" class="btn-primary ml-auto" :disabled="!valid || saving">{{ saving ? 'Saving…' : 'Save' }}</button>
    </template>
  </AppDialog>
</template>
