import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    { path: '/', name: 'trips', component: () => import('@/views/TripsView.vue') },
    { path: '/trip/:id', name: 'trip', component: () => import('@/views/TripView.vue'), props: true },
    { path: '/claude', name: 'claude', component: () => import('@/views/ConnectClaudeView.vue') },
    { path: '/sign-in', name: 'sign-in', component: () => import('@/views/SignInView.vue'), meta: { public: true } },
    { path: '/:pathMatch(.*)*', name: 'not-found', component: () => import('@/views/NotFoundView.vue'), meta: { public: true } },
  ],
  scrollBehavior: (_to, _from, saved) => saved ?? { top: 0 },
})

router.beforeEach(async (to) => {
  const authStore = useAuthStore()
  await authStore.whenReady()
  if (to.name === 'sign-in' && authStore.user) return { name: 'trips' }
  if (!to.meta.public && !authStore.user) return { name: 'sign-in', query: to.fullPath === '/' ? {} : { redirect: to.fullPath } }
})

// On desktop the page scrolls inside the main pane, not the window.
router.afterEach((to, from) => {
  if (to.fullPath !== from.fullPath) document.getElementById('main-scroll')?.scrollTo({ top: 0 })
})

export default router
