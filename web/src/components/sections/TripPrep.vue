<script setup lang="ts">
import { computed, ref } from 'vue'
import { PhCheckSquare, PhPencilSimple, PhPlus, PhSquare, PhTag } from '@phosphor-icons/vue'
import PrepTaskDialog from '../PrepTaskDialog.vue'
import type { PrepTask } from '@/lib/model'
import { setPrepTaskCompleted } from '@/lib/writes'
import { useTripContext } from '@/composables/tripContext'

/** The preparation checklist (PreparationChecklistView), grouped by category. */
const { trip, content } = useTripContext()
const tasks = content.prepTasks

type Filter = 'all' | 'todo' | 'done'
const filter = ref<Filter>('all')
const filters: { value: Filter; label: string }[] = [
  { value: 'all', label: 'All' },
  { value: 'todo', label: 'Not done' },
  { value: 'done', label: 'Done' },
]

const done = computed(() => tasks.value.filter((t) => t.completed).length)
const groups = computed(() => {
  const list = tasks.value.filter((t) => (filter.value === 'all' ? true : filter.value === 'done' ? t.completed : !t.completed))
  const byCategory = new Map<string, PrepTask[]>()
  for (const t of list) byCategory.set(t.category, [...(byCategory.get(t.category) ?? []), t])
  return [...byCategory.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([category, items]) => ({ category, items: items.sort((a, b) => a.name.localeCompare(b.name)) }))
})

const dialog = ref<{ open: boolean; task?: PrepTask }>({ open: false })
const error = ref<string | null>(null)

async function toggle(task: PrepTask) {
  error.value = null
  try {
    await setPrepTaskCompleted(trip.value.id, task.id, !task.completed)
  } catch (err) {
    console.error(err)
    error.value = 'Couldn’t save. Check your connection and try again.'
  }
}
</script>

<template>
  <div class="mx-auto max-w-3xl space-y-5">
    <div v-if="!tasks.length" class="sticker-card-trip p-8 text-center">
      <PhCheckSquare class="mx-auto size-10 text-trip-500" />
      <p class="mt-3 font-display text-2xl font-bold uppercase">No prep tasks yet</p>
      <p class="mt-1 text-sm text-zinc-500">Add packing, documents, or other things to prepare.</p>
      <button class="btn-primary mt-4" @click="dialog = { open: true }"><PhPlus class="size-4" /> Add task</button>
    </div>

    <template v-else>
      <section class="rounded-card bg-trip-50 p-5">
        <p class="tracked-label">Ready to go</p>
        <p class="mt-1 flex items-baseline gap-1.5">
          <span class="font-display text-5xl font-semibold text-trip-700">{{ done }}</span>
          <span class="text-zinc-600">of {{ tasks.length }} done</span>
        </p>
        <div class="mt-3 h-2 overflow-hidden rounded-full bg-trip-200">
          <div class="h-full rounded-full bg-trip-500 transition-all" :style="{ width: `${(done / tasks.length) * 100}%` }" />
        </div>
      </section>

      <div class="flex items-center gap-3">
        <div class="flex flex-1 rounded-xl bg-card-surface p-1 text-sm font-medium">
          <button
            v-for="f in filters" :key="f.value"
            class="flex-1 rounded-lg px-3 py-1.5 transition"
            :class="filter === f.value ? 'bg-white shadow-sm' : 'text-zinc-500'"
            @click="filter = f.value"
          >{{ f.label }}</button>
        </div>
        <button class="btn-primary" @click="dialog = { open: true }"><PhPlus class="size-4" /> Task</button>
      </div>
      <p v-if="error" class="text-sm text-danger">{{ error }}</p>

      <section v-for="group in groups" :key="group.category">
        <h2 class="tracked-label mb-2 flex items-center gap-1.5"><PhTag class="size-3.5" /> {{ group.category }}</h2>
        <ul class="sticker-card-trip divide-y divide-trip-border">
          <li v-for="task in group.items" :key="task.id" class="flex items-start gap-3 px-4 py-3">
            <button class="mt-0.5 shrink-0" :aria-label="task.completed ? 'Mark not done' : 'Mark done'" @click="toggle(task)">
              <PhCheckSquare v-if="task.completed" class="size-6 text-trip-500" weight="fill" />
              <PhSquare v-else class="size-6 text-zinc-400" />
            </button>
            <span class="min-w-0 flex-1">
              <span class="block font-medium" :class="task.completed && 'text-zinc-400 line-through'">{{ task.name }}</span>
              <span v-if="task.notes" class="block text-sm whitespace-pre-line text-zinc-500">{{ task.notes }}</span>
            </span>
            <button class="icon-btn size-8 shrink-0" aria-label="Edit task" @click="dialog = { open: true, task }"><PhPencilSimple class="size-4" /></button>
          </li>
        </ul>
      </section>
    </template>

    <PrepTaskDialog v-model:open="dialog.open" :task="dialog.task" />
  </div>
</template>
