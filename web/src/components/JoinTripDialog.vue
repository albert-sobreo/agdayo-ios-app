<script setup lang="ts">
import { ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import AppDialog from './AppDialog.vue'
import { JoinError, joinTrip } from '@/lib/writes'
import { useAuthStore } from '@/stores/auth'

const open = defineModel<boolean>('open', { required: true })
const authStore = useAuthStore()
const router = useRouter()

const code = ref('')
const joining = ref(false)
const error = ref<string | null>(null)

watch(open, (isOpen) => {
  if (isOpen) {
    code.value = ''
    error.value = null
  }
})

async function join() {
  const uid = authStore.user?.uid
  if (!uid || !code.value.trim()) return
  joining.value = true
  error.value = null
  try {
    const id = await joinTrip(code.value, uid)
    open.value = false
    await router.push({ name: 'trip', params: { id } })
  } catch (err) {
    error.value = err instanceof JoinError ? err.message : 'Couldn’t join the trip. Check your connection and try again.'
    if (!(err instanceof JoinError)) console.error(err)
  } finally {
    joining.value = false
  }
}
</script>

<template>
  <AppDialog v-model:open="open" title="Join a trip" description="Enter the code or paste the invite link someone shared with you.">
    <form id="join-form" @submit.prevent="join">
      <label class="label" for="join-code">Invitation code</label>
      <input id="join-code" v-model="code" class="input font-mono tracking-widest uppercase" placeholder="ABC234" autocomplete="off" autofocus />
      <p v-if="error" class="mt-3 text-sm text-danger">{{ error }}</p>
    </form>
    <template #footer>
      <button type="button" class="btn-ghost" @click="open = false">Cancel</button>
      <button type="submit" form="join-form" class="btn-primary ml-auto" :disabled="!code.trim() || joining">
        {{ joining ? 'Joining…' : 'Join' }}
      </button>
    </template>
  </AppDialog>
</template>
