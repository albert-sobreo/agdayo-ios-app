import { onScopeDispose, ref, watch, type Ref } from 'vue'
import { collection, doc, getDoc, onSnapshot, type DocumentData, type Unsubscribe } from 'firebase/firestore'
import { db } from '@/firebase'
import {
  toActivity, toBudgetCategory, toDayNote, toExpense, toIdea, toMember, toPoll, toPrepTask, toSettlement, toStay,
  toTransport, toUserProfile,
  type Activity, type BudgetCategory, type DayNote, type Expense, type Idea, type Member, type Poll, type PrepTask,
  type Settlement, type Stay, type Transport, type UserProfile,
} from '@/lib/model'
import { ensureMembership } from '@/lib/writes'
import { useAuthStore } from '@/stores/auth'
import { useTripsStore } from '@/stores/trips'

/**
 * Everything inside one trip, live (TripContentSyncCoordinator in the app).
 * Changes from the iPhone app, other members or Claude show up right away.
 */
export function useTripContent(tripId: Ref<string>) {
  const authStore = useAuthStore()
  const tripsStore = useTripsStore()

  const activities = ref<Activity[]>([])
  const stays = ref<Stay[]>([])
  const transport = ref<Transport[]>([])
  const dayNotes = ref<DayNote[]>([])
  const members = ref<Member[]>([])
  const budgetCategories = ref<BudgetCategory[]>([])
  const expenses = ref<Expense[]>([])
  const settlements = ref<Settlement[]>([])
  const prepTasks = ref<PrepTask[]>([])
  const polls = ref<Poll[]>([])
  const ideas = ref<Idea[]>([])
  const profiles = ref<Record<string, UserProfile>>({})
  const error = ref<string | null>(null)

  let unsubs: Unsubscribe[] = []
  const stop = () => {
    unsubs.forEach((unsub) => unsub())
    unsubs = []
  }

  function listen<T>(name: string, decode: (id: string, d: DocumentData) => T | null, target: Ref<T[]>) {
    unsubs.push(
      onSnapshot(
        collection(db, 'trips', tripId.value, name),
        (snapshot) => {
          target.value = snapshot.docs.map((d) => decode(d.id, d.data())).filter((x): x is T => x !== null)
        },
        (err) => {
          console.warn(`Could not load ${name}`, err)
          error.value = 'Some of this trip couldn’t load. You may not be a member of it any more.'
        },
      ),
    )
  }

  async function loadProfiles(list: Member[]) {
    for (const member of list) {
      if (profiles.value[member.uid]) continue
      try {
        const snapshot = await getDoc(doc(db, 'users', member.uid))
        profiles.value[member.uid] = toUserProfile(member.uid, snapshot.data())
      } catch {
        profiles.value[member.uid] = toUserProfile(member.uid, undefined)
      }
    }
  }

  watch(
    [tripId, () => authStore.user?.uid, () => tripsStore.trip(tripId.value)?.ownerUID],
    async ([id, uid, ownerUID]) => {
      stop()
      error.value = null
      activities.value = []
      stays.value = []
      transport.value = []
      dayNotes.value = []
      members.value = []
      budgetCategories.value = []
      expenses.value = []
      settlements.value = []
      prepTasks.value = []
      polls.value = []
      ideas.value = []
      if (!id || !uid || ownerUID === undefined) return
      try {
        // Same order as the app: listeners fail for good if they start before the membership doc exists.
        await ensureMembership(id, uid, ownerUID === uid ? 'owner' : 'member')
      } catch (err) {
        console.warn('Could not confirm membership', err)
      }
      if (id !== tripId.value) return
      listen('activities', toActivity, activities)
      listen('accommodations', toStay, stays)
      listen('transportSegments', toTransport, transport)
      listen('dayNotes', toDayNote, dayNotes)
      listen('budgetCategories', toBudgetCategory, budgetCategories)
      listen('expenses', toExpense, expenses)
      listen('settlements', toSettlement, settlements)
      listen('preparationTasks', toPrepTask, prepTasks)
      listen('polls', toPoll, polls)
      listen('ideas', toIdea, ideas)
      unsubs.push(
        onSnapshot(collection(db, 'trips', id, 'members'), (snapshot) => {
          members.value = snapshot.docs.map((d) => toMember(d.id, d.data()))
          void loadProfiles(members.value)
        }),
      )
    },
    { immediate: true },
  )

  onScopeDispose(stop)

  return {
    activities, stays, transport, dayNotes, members, profiles, error,
    budgetCategories, expenses, settlements, prepTasks, polls, ideas,
  }
}
