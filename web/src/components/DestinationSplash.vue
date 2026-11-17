<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { PhCaretLeft, PhCaretRight } from '@phosphor-icons/vue'
import { destinations } from '@/lib/destinations'

/** Full-bleed photos of Philippine destinations that change every few seconds, like the original web app. */
defineProps<{ compact?: boolean }>()

const index = ref(Math.floor(Math.random() * destinations.length))
const current = computed(() => destinations[index.value]!)
const year = new Date().getFullYear()
let timer: ReturnType<typeof setInterval> | undefined

const reducedMotion = typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches

function go(step: number) {
  index.value = (index.value + step + destinations.length) % destinations.length
  restart()
}

function restart() {
  clearInterval(timer)
  if (!reducedMotion) timer = setInterval(() => (index.value = (index.value + 1) % destinations.length), 9000)
}

/** Warm the cache so the next photo fades in instead of loading in. */
function preload() {
  for (const d of destinations) {
    const img = new Image()
    img.src = `/images/${d.key}-sm.webp`
  }
}

onMounted(() => {
  restart()
  setTimeout(preload, 1500)
})
onUnmounted(() => clearInterval(timer))
</script>

<template>
  <div class="relative isolate flex flex-col overflow-hidden bg-ink text-white">
    <TransitionGroup name="photo">
      <picture :key="current.key" class="absolute inset-0 -z-10">
        <source media="(min-width: 1024px)" :srcset="`/images/${current.key}.webp`" />
        <img :src="`/images/${current.key}-sm.webp`" alt="" class="size-full object-cover" />
      </picture>
    </TransitionGroup>
    <div class="absolute inset-0 -z-10 bg-gradient-to-t from-black/70 via-black/20 to-black/30" />

    <div class="flex items-center justify-between p-5 lg:p-9">
      <slot name="top" />
    </div>

    <div class="flex flex-1 items-end lg:items-center">
      <button class="hidden h-full w-20 shrink-0 items-center justify-center text-white/0 transition hover:text-white/80 lg:flex" aria-label="Previous place" @click="go(-1)">
        <PhCaretLeft class="size-8" />
      </button>
      <Transition name="title" mode="out-in">
        <div :key="current.key" class="min-w-0 flex-1 px-5 pb-10 lg:px-0 lg:pb-0">
          <p class="title-in text-sm text-white/90 lg:text-base">
            {{ current.lead }} <span class="font-baybayin" :style="{ color: current.color }">{{ current.name }}</span>
          </p>
          <h2
            class="title-in title-in-1 font-display leading-[0.85] font-black uppercase"
            :class="compact ? 'text-6xl' : 'text-7xl lg:text-[9rem] xl:text-[11rem]'"
            :style="{ color: current.color, textShadow: `${compact ? 4 : 6}px ${compact ? 4 : 6}px 0 ${current.shadow}` }"
          >
            {{ current.name }}
          </h2>
          <p v-if="!compact" class="title-in title-in-2 mt-4 max-w-xl text-sm leading-relaxed text-white/80 lg:text-base">
            {{ current.description }}
          </p>
        </div>
      </Transition>
      <button class="hidden h-full w-20 shrink-0 items-center justify-center text-white/0 transition hover:text-white/80 lg:flex" aria-label="Next place" @click="go(1)">
        <PhCaretRight class="size-8" />
      </button>
    </div>

    <div v-if="!compact" class="flex items-center justify-between gap-4 p-5 text-xs text-white/60 lg:px-9 lg:pb-7">
      <span>© Agdayo {{ year }}</span>
      <div class="flex gap-1.5">
        <button
          v-for="(d, i) in destinations"
          :key="d.key"
          class="h-1.5 rounded-full transition-all"
          :class="i === index ? 'w-6 bg-white' : 'w-1.5 bg-white/40 hover:bg-white/70'"
          :aria-label="d.name"
          @click="go(i - index)"
        />
      </div>
      <Transition name="fade" mode="out-in"><span :key="current.credits" class="text-right">{{ current.credits }}</span></Transition>
    </div>
  </div>
</template>

<style scoped>
.photo-enter-active,
.photo-leave-active {
  transition: opacity 900ms ease;
}
.photo-enter-from,
.photo-leave-to {
  opacity: 0;
}
.fade-enter-active,
.fade-leave-active,
.title-leave-active {
  transition: opacity 300ms ease;
}
.fade-enter-from,
.fade-leave-to,
.title-leave-to {
  opacity: 0;
}
.title-in {
  animation: title-in 600ms ease both;
}
.title-in-1 {
  animation-delay: 100ms;
}
.title-in-2 {
  animation-delay: 200ms;
}
@keyframes title-in {
  from {
    opacity: 0;
    transform: translateY(12px);
  }
}
@media (prefers-reduced-motion: reduce) {
  .title-in {
    animation: none;
  }
}
</style>
