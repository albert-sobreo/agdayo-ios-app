<script setup lang="ts">
import { computed } from 'vue'
import { useRouter } from 'vue-router'
import { DropdownMenuContent, DropdownMenuItem, DropdownMenuPortal, DropdownMenuRoot, DropdownMenuTrigger } from 'reka-ui'
import { PhCaretUpDown, PhSignOut, PhSparkle } from '@phosphor-icons/vue'
import { useAuthStore } from '@/stores/auth'
import { useTripsStore } from '@/stores/trips'

/** The person's avatar with sign out. `full` shows their name and version beside it (sidebar footer). */
defineProps<{ full?: boolean }>()

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
  <DropdownMenuRoot v-if="authStore.user">
    <DropdownMenuTrigger
      class="flex items-center gap-2.5 rounded-xl text-left transition hover:bg-black/5"
      :class="full ? 'w-full p-2' : 'rounded-full p-0.5'"
      aria-label="Account"
    >
      <img v-if="authStore.user.photoURL" :src="authStore.user.photoURL" alt="" class="size-8 shrink-0 rounded-full object-cover" referrerpolicy="no-referrer" />
      <span v-else class="flex size-8 shrink-0 items-center justify-center rounded-full bg-brand-rose text-sm font-bold text-white">{{ initial }}</span>
      <template v-if="full">
        <span class="min-w-0 flex-1">
          <span class="block truncate text-sm font-semibold">{{ name }}</span>
          <span class="block truncate text-xs" :class="tripsStore.isUnlocked ? 'text-mint-text' : 'text-zinc-500'">
            {{ tripsStore.isUnlocked ? 'Full version' : 'Free version' }}
          </span>
        </span>
        <PhCaretUpDown class="size-4 shrink-0 text-zinc-400" />
      </template>
    </DropdownMenuTrigger>
    <DropdownMenuPortal>
      <DropdownMenuContent :align="full ? 'start' : 'end'" :side="full ? 'top' : 'bottom'" :side-offset="6" class="z-50 min-w-56 rounded-dense border border-secondary bg-white p-1 shadow-sticker">
        <div class="px-3 py-2">
          <p class="truncate text-sm font-semibold">{{ name }}</p>
          <p class="truncate text-xs text-zinc-500">{{ authStore.user.email }}</p>
        </div>
        <DropdownMenuItem class="menu-item" @select="router.push({ name: 'claude' })"><PhSparkle class="size-4" /> Connect Claude</DropdownMenuItem>
        <DropdownMenuItem class="menu-item" @select="signOut"><PhSignOut class="size-4" /> Sign out</DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenuPortal>
  </DropdownMenuRoot>
</template>
