<script setup lang="ts">
import { ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { PhLock, PhEnvelopeSimple, PhUser } from '@phosphor-icons/vue'
import DestinationSplash from '@/components/DestinationSplash.vue'
import { authErrorMessage, useAuthStore } from '@/stores/auth'

const authStore = useAuthStore()
const router = useRouter()
const route = useRoute()

type Mode = 'sign-in' | 'sign-up' | 'reset'
const mode = ref<Mode>('sign-in')
const name = ref('')
const email = ref('')
const password = ref('')
const busy = ref(false)
const error = ref<string | null>(null)
const notice = ref<string | null>(null)

async function run(action: () => Promise<void>) {
  busy.value = true
  error.value = null
  notice.value = null
  try {
    await action()
    if (mode.value !== 'reset') {
      const redirect = typeof route.query.redirect === 'string' && route.query.redirect.startsWith('/') ? route.query.redirect : '/'
      await router.replace(redirect)
    }
  } catch (err) {
    error.value = authErrorMessage(err)
  } finally {
    busy.value = false
  }
}

const google = () => run(authStore.signInWithGoogle)
const apple = () => run(authStore.signInWithApple)
function submit() {
  if (mode.value === 'sign-in') return run(() => authStore.signInWithEmail(email.value, password.value))
  if (mode.value === 'sign-up') return run(() => authStore.signUpWithEmail(name.value, email.value, password.value))
  if (mode.value === 'reset') {
    return run(async () => {
      await authStore.resetPassword(email.value)
      notice.value = 'If there’s an account for that email, a reset link is on its way.'
    })
  }
}
function show(next: Mode) {
  mode.value = next
  error.value = null
  notice.value = null
}
</script>

<template>
  <div class="flex min-h-dvh flex-col bg-canvas lg:h-dvh lg:flex-row">
    <!-- Photos: full height beside the form on wide screens, a banner on phones -->
    <DestinationSplash class="h-[42dvh] min-h-72 lg:hidden" compact>
      <template #top>
        <img src="/images/logo-agdayo.webp" alt="" width="848" height="496" class="h-10 w-auto" />
      </template>
    </DestinationSplash>
    <DestinationSplash class="hidden lg:flex lg:flex-1">
      <template #top>
        <img src="/images/logo-agdayo.webp" alt="" width="848" height="496" class="h-12 w-auto" />
        <span class="rounded-full bg-white/15 px-3 py-1 text-xs font-semibold tracking-wider uppercase backdrop-blur">Web beta</span>
      </template>
    </DestinationSplash>

    <!-- Sign-in -->
    <main class="relative z-10 -mt-7 flex flex-1 items-start justify-center rounded-t-card bg-canvas px-6 pt-8 pb-10 lg:mt-0 lg:w-[440px] lg:flex-none lg:items-center lg:overflow-y-auto lg:rounded-none lg:px-10">
      <div class="w-full max-w-sm">
        <div class="flex flex-col items-center text-center">
          <span class="text-sm font-bold text-zinc-400">Start your travels in</span>
          <img src="/images/logo-agdayo.webp" alt="Agdayo" width="848" height="496" class="mt-3 w-44 lg:w-52" />
          <span class="font-baybayin mt-3 block w-full truncate text-[0.7rem] text-zinc-400" aria-hidden="true">agdayoagdayoagdayoagdayoagdayoagdayoagdayoagdayo</span>
          <p class="mt-3 text-sm text-zinc-500">Use the same account as the Agdayo iPhone app.</p>
        </div>

        <div class="mt-7 space-y-2.5">
          <button class="btn-secondary w-full py-3" :disabled="busy" @click="google">
            <img src="/google-logo.svg" alt="" class="size-4.5" /> Continue with Google
          </button>
          <button class="btn-primary w-full py-3" :disabled="busy" @click="apple">
            <svg viewBox="0 0 24 24" class="size-4.5 fill-current" aria-hidden="true"><path d="M16.37 12.6c-.02-2.3 1.88-3.4 1.96-3.46-1.07-1.56-2.73-1.77-3.32-1.8-1.41-.14-2.76.83-3.48.83-.72 0-1.82-.81-3-.79-1.54.02-2.96.9-3.76 2.28-1.6 2.78-.41 6.9 1.15 9.16.76 1.1 1.67 2.34 2.86 2.3 1.15-.05 1.58-.74 2.97-.74 1.38 0 1.78.74 2.99.72 1.24-.02 2.02-1.12 2.77-2.23.88-1.28 1.24-2.52 1.26-2.59-.03-.01-2.4-.92-2.42-3.66zM14.1 5.86c.63-.77 1.06-1.83.94-2.89-.91.04-2.02.61-2.67 1.37-.58.67-1.1 1.76-.96 2.8 1.02.08 2.06-.52 2.69-1.28z"/></svg>
            Continue with Apple
          </button>
        </div>

        <div class="my-6 flex items-center gap-3 text-xs text-zinc-400">
          <span class="h-px flex-1 bg-secondary" /> or use email <span class="h-px flex-1 bg-secondary" />
        </div>

        <form class="space-y-3" @submit.prevent="submit">
          <div v-if="mode === 'sign-up'" class="relative">
            <label class="sr-only" for="name">Name</label>
            <PhUser class="pointer-events-none absolute top-1/2 left-3.5 size-4 -translate-y-1/2 text-zinc-400" />
            <input id="name" v-model="name" class="input pl-10" placeholder="Your name" autocomplete="name" />
          </div>
          <div class="relative">
            <label class="sr-only" for="email">Email</label>
            <PhEnvelopeSimple class="pointer-events-none absolute top-1/2 left-3.5 size-4 -translate-y-1/2 text-zinc-400" />
            <input id="email" v-model="email" type="email" class="input pl-10" placeholder="Email" autocomplete="email" required />
          </div>
          <div v-if="mode !== 'reset'" class="relative">
            <label class="sr-only" for="password">Password</label>
            <PhLock class="pointer-events-none absolute top-1/2 left-3.5 size-4 -translate-y-1/2 text-zinc-400" />
            <input
              id="password"
              v-model="password"
              type="password"
              class="input pl-10"
              placeholder="Password"
              :autocomplete="mode === 'sign-up' ? 'new-password' : 'current-password'"
              minlength="6"
              required
            />
          </div>
          <div v-if="mode === 'sign-in'" class="text-right">
            <button type="button" class="text-xs font-medium text-zinc-500 hover:text-ink" @click="show('reset')">Forgot password?</button>
          </div>
          <button type="submit" class="btn-primary w-full py-3" :disabled="busy">
            {{ busy ? 'One moment…' : mode === 'sign-in' ? 'Sign in' : mode === 'sign-up' ? 'Create account' : 'Send reset link' }}
          </button>
        </form>

        <p v-if="error" class="mt-4 rounded-xl bg-danger/10 p-3 text-sm text-danger" role="alert">{{ error }}</p>
        <p v-if="notice" class="mt-4 rounded-xl bg-mint p-3 text-sm text-mint-text">{{ notice }}</p>

        <p class="mt-6 text-center text-sm text-zinc-500">
          <template v-if="mode === 'sign-in'">No account yet? <button class="font-semibold text-maroon" @click="show('sign-up')">Sign up</button></template>
          <template v-else>Already have an account? <button class="font-semibold text-maroon" @click="show('sign-in')">Sign in</button></template>
        </p>
      </div>
    </main>
  </div>
</template>
