<script setup lang="ts">
import { computed, onScopeDispose, ref } from 'vue'
import { PhCheck, PhCopy, PhSparkle } from '@phosphor-icons/vue'
import { auth } from '@/firebase'
import { config } from '@/config'

/**
 * Connect Claude (ConnectClaudeView in the app). The person adds Agdayo as a custom
 * connector in their own Claude and signs in on its page with a one-time code from here.
 */
const connectorUrl = `${config.workerUrl.replace(/\/+$/, '')}/mcp`

type CodeState = { kind: 'idle' } | { kind: 'loading' } | { kind: 'ready'; code: string; expiresAt: number } | { kind: 'failed'; message: string }
const state = ref<CodeState>({ kind: 'idle' })
const now = ref(Date.now())
const timer = setInterval(() => (now.value = Date.now()), 1000)
onScopeDispose(() => clearInterval(timer))

const copiedUrl = ref(false)
const copiedCode = ref(false)

const remaining = computed(() => {
  if (state.value.kind !== 'ready') return ''
  const seconds = Math.max(0, Math.round((state.value.expiresAt - now.value) / 1000))
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`
})
const expired = computed(() => state.value.kind === 'ready' && now.value >= state.value.expiresAt)

async function getCode() {
  state.value = { kind: 'loading' }
  copiedCode.value = false
  try {
    const token = await auth.currentUser?.getIdToken()
    if (!token) throw new Error('Sign in to use this.')
    const response = await fetch(`${config.workerUrl.replace(/\/+$/, '')}/v1/connect-code`, {
      method: 'POST',
      headers: { authorization: `Bearer ${token}` },
    })
    const body = (await response.json().catch(() => ({}))) as { code?: string; expiresInSeconds?: number; error?: string }
    if (!response.ok || !body.code) throw new Error(body.error || 'Couldn’t get a code. Try again.')
    state.value = { kind: 'ready', code: body.code, expiresAt: Date.now() + (body.expiresInSeconds ?? 600) * 1000 }
  } catch (err) {
    state.value = { kind: 'failed', message: err instanceof TypeError ? 'Couldn’t reach the Agdayo server. Try again.' : (err as Error).message }
  }
}

async function copy(text: string, which: 'url' | 'code') {
  await navigator.clipboard.writeText(text)
  const flag = which === 'url' ? copiedUrl : copiedCode
  flag.value = true
  setTimeout(() => (flag.value = false), 1500)
}
</script>

<template>
  <div class="mx-auto max-w-2xl space-y-4">
    <section class="rounded-card bg-blush p-5 sm:p-6">
      <PhSparkle class="size-7 text-maroon" weight="fill" />
      <h2 class="mt-2 font-display text-4xl font-semibold text-maroon uppercase">Connect Claude</h2>
      <p class="mt-1 text-maroon/85">
        Plan a trip by chatting with Claude, then have it write the plan straight into Agdayo: activities, stays, transport and notes.
        Works on Claude’s free plan.
      </p>
    </section>

    <section class="sticker-card p-5">
      <p class="tracked-label">1. Add Agdayo to Claude</p>
      <p class="mt-2 text-sm text-zinc-700">
        In the Claude phone app, open <b>Settings › Connectors</b>. On claude.ai or the desktop app, open <b>Settings › Plugins</b> (just below Artifacts).
        Add a custom connector named <b>Agdayo</b> with this address:
      </p>
      <button class="mt-3 flex w-full items-center gap-3 rounded-xl border border-secondary bg-white px-3 py-2.5 text-left hover:bg-card-surface" @click="copy(connectorUrl, 'url')">
        <span class="min-w-0 flex-1 truncate font-mono text-sm">{{ connectorUrl }}</span>
        <PhCheck v-if="copiedUrl" class="size-4 text-mint-text" /><PhCopy v-else class="size-4 text-zinc-500" />
      </button>
    </section>

    <section class="sticker-card p-5">
      <p class="tracked-label">2. Sign in with a code</p>
      <p class="mt-2 text-sm text-zinc-700">Click Connect in Claude. On the Agdayo page that opens, enter this code:</p>
      <div class="mt-3">
        <button v-if="state.kind === 'idle'" class="btn-primary" @click="getCode">Get code</button>
        <p v-else-if="state.kind === 'loading'" class="text-sm text-zinc-500">Getting a code…</p>
        <template v-else-if="state.kind === 'ready'">
          <button v-if="expired" class="btn-secondary" @click="getCode">Code expired. Get a new code</button>
          <div v-else>
            <div class="flex items-center gap-3">
              <span class="font-mono text-3xl font-semibold tracking-wider select-all">{{ state.code }}</span>
              <button class="icon-btn" aria-label="Copy code" @click="copy(state.code, 'code')">
                <PhCheck v-if="copiedCode" class="size-5 text-mint-text" /><PhCopy v-else class="size-5" />
              </button>
            </div>
            <p class="mt-1 text-xs text-zinc-500">Expires in {{ remaining }}</p>
          </div>
        </template>
        <div v-else>
          <p class="text-sm text-danger">{{ state.message }}</p>
          <button class="btn-secondary mt-2" @click="getCode">Try again</button>
        </div>
      </div>
      <p class="mt-3 text-xs text-zinc-500">A code works once and lasts 10 minutes. If you sign in to Agdayo with Google, you can choose Continue with Google there instead.</p>
    </section>

    <p class="px-1 text-xs text-zinc-500">
      Claude only sees and changes trips you own or have joined, and asks before each change. To disconnect, remove Agdayo in Claude:
      Settings › Connectors on the phone, or Settings › Plugins on claude.ai and desktop.
    </p>
  </div>
</template>
