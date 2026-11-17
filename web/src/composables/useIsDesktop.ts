import { useMediaQuery } from '@vueuse/core'

/** Wide enough for the two-pane layout (trip list on the left, trip on the right). Matches Tailwind's lg. */
export const useIsDesktop = () => useMediaQuery('(min-width: 1024px)')
