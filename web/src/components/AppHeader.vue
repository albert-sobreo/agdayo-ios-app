<script setup lang="ts">
import AccountMenu from './AccountMenu.vue'
</script>

<template>
  <!-- Phones and tablets only; desktop has the sidebar instead. -->
  <header class="sticky top-0 z-30 border-b border-black/5 bg-canvas/85 backdrop-blur lg:hidden">
    <div class="flex h-14 items-center justify-between px-4">
      <RouterLink to="/" class="flex items-center gap-2">
        <img src="/images/logo-agdayo.webp" alt="Agdayo" width="848" height="496" class="h-8 w-auto" />
        <span class="rounded-pill bg-mint px-1.5 py-0.5 text-[10px] font-bold tracking-wider text-mint-text uppercase">Beta</span>
      </RouterLink>
      <AccountMenu />
    </div>
  </header>
</template>
