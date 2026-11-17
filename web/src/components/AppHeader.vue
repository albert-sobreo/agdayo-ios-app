<script setup lang="ts">
import { computed } from 'vue'
import { useRouter } from 'vue-router'
import { DropdownMenuContent, DropdownMenuItem, DropdownMenuPortal, DropdownMenuRoot, DropdownMenuTrigger } from 'reka-ui'
import { PhSignOut } from '@phosphor-icons/vue'
import { useAuthStore } from '@/stores/auth'
import { useTripsStore } from '@/stores/trips'

const authStore = useAuthStore()
const tripsStore = useTripsStore()
const router = useRouter()

const name = computed(() => tripsStore.profile?.displayName || authStore.user?.displayName || authStore.user?.email || 'Traveler')
const initial = computed(() => name.value.trim().charAt(0).toUpperCase() || 'A')

async function signOut() {
  await authStore.signOut()
  await router.replace({ name: 'sign-in' })
}
</script>

<template>
  <header class="sticky top-0 z-30 border-b border-black/5 bg-canvas/85 backdrop-blur">
    <div class="mx-auto flex h-14 max-w-5xl items-center justify-between px-4">
      <RouterLink to="/" class="flex items-center gap-2">
        <img src="/images/logo-agdayo.webp" alt="" width="848" height="496" class="h-8 w-auto" />
        <span class="font-display text-2xl font-bold tracking-wide text-maroon uppercase">Agdayo</span>
        <span class="rounded-pill bg-mint px-1.5 py-0.5 text-[10px] font-bold tracking-wider text-mint-text uppercase">Beta</span>
      </RouterLink>
      <DropdownMenuRoot v-if="authStore.user">
        <DropdownMenuTrigger class="flex items-center gap-2 rounded-full p-0.5 transition hover:bg-black/5" aria-label="Account">
          <img v-if="authStore.user.photoURL" :src="authStore.user.photoURL" alt="" class="size-8 rounded-full object-cover" referrerpolicy="no-referrer" />
          <span v-else class="flex size-8 items-center justify-center rounded-full bg-brand-rose text-sm font-bold text-white">{{ initial }}</span>
        </DropdownMenuTrigger>
        <DropdownMenuPortal>
          <DropdownMenuContent align="end" :side-offset="6" class="z-50 min-w-56 rounded-dense border border-secondary bg-white p-1 shadow-sticker">
            <div class="px-3 py-2">
              <p class="truncate text-sm font-semibold">{{ name }}</p>
              <p class="truncate text-xs text-zinc-500">{{ authStore.user.email }}</p>
              <p class="mt-1 text-xs font-medium" :class="tripsStore.isUnlocked ? 'text-mint-text' : 'text-zinc-500'">
                {{ tripsStore.isUnlocked ? 'Full version' : 'Free version' }}
              </p>
            </div>
            <DropdownMenuItem class="flex cursor-pointer items-center gap-2 rounded-lg px-3 py-2 text-sm outline-none data-highlighted:bg-black/5" @select="signOut">
              <PhSignOut class="size-4" /> Sign out
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenuPortal>
      </DropdownMenuRoot>
    </div>
  </header>
</template>
