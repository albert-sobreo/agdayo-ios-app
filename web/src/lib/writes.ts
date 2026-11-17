import type { User } from 'firebase/auth'
import {
  arrayRemove, arrayUnion, collection, deleteDoc, deleteField, doc, getCountFromServer, getDoc, getDocs, serverTimestamp,
  setDoc, updateDoc, writeBatch, type FieldValue,
} from 'firebase/firestore'
import { db } from '@/firebase'
import type { Activity, CostSplit, Expense, Idea, Poll, Stay, Transport, StayType, TransportMode, TripTheme } from './model'

/**
 * Every write the web makes, in the same field names and types as the iPhone app
 * (TripMembershipService.swift and the *Sync.swift DTOs) and the Worker (worker/src/trips.ts).
 *
 * Edits use updateDoc with only the fields the web form owns, so fields the web
 * doesn't show (cost splits, budget categories, placeID, createdBy) are kept.
 */

export const freeTripLimit = 2
export const freeMemberLimit = 3

/** Swift's UUID().uuidString is upper case; the app's document IDs follow it. */
export function newId(): string {
  return crypto.randomUUID().toUpperCase()
}

/** Matches TripMembershipService.generateRandomCode. */
export function joinCode(length = 6): string {
  const chars = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ'
  const random = crypto.getRandomValues(new Uint32Array(length))
  return Array.from(random, (n) => chars[n % chars.length]).join('')
}

type Fields = Record<string, unknown>

/** Firestore rejects undefined; leave those keys out. */
function defined(fields: Fields): Fields {
  return Object.fromEntries(Object.entries(fields).filter(([, value]) => value !== undefined))
}

/** The cost-split and budget fields, as the app writes them (splitAmounts is left out when empty). */
export interface SplitInput {
  paidByUID: string | null
  splitUIDs: string[]
  splitAmounts: Record<string, number>
  budgetCategoryID: string | null
  budgetMemberUID: string | null
}

function splitFieldsForCreate(split: SplitInput): Fields {
  return defined({
    paidByUID: split.paidByUID ?? undefined,
    splitUIDs: split.splitUIDs,
    splitAmounts: Object.keys(split.splitAmounts).length ? split.splitAmounts : undefined,
    budgetCategoryID: split.budgetCategoryID ?? undefined,
    budgetMemberUID: split.budgetMemberUID ?? undefined,
  })
}

function splitFieldsForUpdate(split: SplitInput): Fields {
  return {
    paidByUID: split.paidByUID ?? deleteField(),
    splitUIDs: split.splitUIDs,
    splitAmounts: Object.keys(split.splitAmounts).length ? split.splitAmounts : deleteField(),
    budgetCategoryID: split.budgetCategoryID ?? deleteField(),
    budgetMemberUID: split.budgetMemberUID ?? deleteField(),
  }
}

export function splitOf(item: CostSplit | undefined): SplitInput {
  return {
    paidByUID: item?.paidByUID ?? null,
    splitUIDs: [...(item?.splitUIDs ?? [])],
    splitAmounts: { ...item?.splitAmounts },
    budgetCategoryID: item?.budgetCategoryID ?? null,
    budgetMemberUID: item?.budgetMemberUID ?? null,
  }
}

const tripRef = (tripId: string) => doc(db, 'trips', tripId)
const itemRef = (tripId: string, sub: string, id: string) => doc(db, 'trips', tripId, sub, id)

// MARK: Users

/** Same as UserDirectoryService.ensureUserDocument. */
export async function ensureUserDocument(user: User): Promise<void> {
  const ref = doc(db, 'users', user.uid)
  const snapshot = await getDoc(ref)
  const data: Fields = { updatedAt: serverTimestamp() }
  if (user.photoURL) data.photoURL = user.photoURL
  if (snapshot.exists()) {
    const stored = String(snapshot.data().displayName ?? '')
    const storedEmail = String(snapshot.data().email ?? '')
    const isFallback = !stored || stored === 'Traveler' || stored === storedEmail || stored.includes('@')
    if (isFallback && user.displayName && user.displayName !== stored) data.displayName = user.displayName
    await updateDoc(ref, data)
  } else {
    await setDoc(
      ref,
      {
        ...data,
        uid: user.uid,
        displayName: user.displayName ?? user.email ?? 'Traveler',
        email: user.email ?? '',
        createdAt: serverTimestamp(),
      },
      { merge: true },
    )
  }
}

// MARK: Trips

export interface TripInput {
  name: string
  location: string
  theme: TripTheme
  startDate: Date
  endDate: Date
  currency: string
  tripDescription: string
}

/** Same steps and order as TripMembershipService.createTripRecord (the rules check each one). */
export async function createTrip(uid: string, input: TripInput, ownerUnlocked: boolean): Promise<string> {
  const tripId = newId()
  const code = joinCode()
  await setDoc(tripRef(tripId), {
    ownerUID: uid,
    name: input.name,
    location: input.location,
    theme: input.theme,
    startDate: input.startDate,
    endDate: input.endDate,
    overallBudget: 0,
    currency: input.currency,
    tripDescription: input.tripDescription,
    memberBudgets: {},
    ownerUnlocked,
    joinCode: code,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  })
  await setDoc(doc(db, 'tripJoinCodes', code), { tripID: tripId, createdAt: serverTimestamp() })
  await setDoc(doc(db, 'trips', tripId, 'members', uid), { uid, role: 'owner', joinedAt: serverTimestamp() })
  await setDoc(doc(db, 'users', uid), { memberOfTripIDs: arrayUnion(tripId) }, { merge: true })
  return tripId
}

export async function updateTrip(tripId: string, input: TripInput, locationChanged: boolean): Promise<void> {
  await updateDoc(tripRef(tripId), {
    name: input.name,
    location: input.location,
    theme: input.theme,
    startDate: input.startDate,
    endDate: input.endDate,
    currency: input.currency,
    tripDescription: input.tripDescription,
    // The old pin would point at the old place. The app sets a new one when it's picked there.
    ...(locationChanged ? { latitude: deleteField(), longitude: deleteField() } : {}),
    updatedAt: serverTimestamp(),
  })
}

export class JoinError extends Error {}

/** Port of TripMembershipService.joinTrip, including the free 3-person limit. */
export async function joinTrip(input: string, uid: string): Promise<string> {
  const code = extractJoinCode(input)
  if (!code) throw new JoinError('Enter the invitation code.')
  const codeDoc = await getDoc(doc(db, 'tripJoinCodes', code))
  const tripId = codeDoc.exists() ? codeDoc.data().tripID : undefined
  if (typeof tripId !== 'string') throw new JoinError('The invitation code is invalid or does not exist.')

  const tripDoc = await getDoc(tripRef(tripId))
  if (!tripDoc.exists()) throw new JoinError('The trip for this code could not be found.')

  const user = await getDoc(doc(db, 'users', uid))
  const ids: unknown = user.data()?.memberOfTripIDs
  if (Array.isArray(ids) && ids.some((id) => String(id).toUpperCase() === tripId.toUpperCase())) {
    throw new JoinError('You are already a member of this trip.')
  }

  const ownerUnlocked = tripDoc.data().ownerUnlocked ?? true
  if (ownerUnlocked === false) {
    const count = await getCountFromServer(collection(db, 'trips', tripId, 'members'))
    if (count.data().count >= freeMemberLimit) {
      throw new JoinError(
        `This trip is full. Free trips hold up to ${freeMemberLimit} people. Ask the trip owner to unlock Agdayo in the iPhone app to add more.`,
      )
    }
  }

  await setDoc(doc(db, 'trips', tripId, 'members', uid), { uid, role: 'member', joinedAt: serverTimestamp() })
  await setDoc(doc(db, 'users', uid), { memberOfTripIDs: arrayUnion(tripId) }, { merge: true })
  return tripId
}

export function extractJoinCode(input: string): string {
  const trimmed = input.trim()
  try {
    const code = new URL(trimmed).searchParams.get('code')
    if (code) return code.trim().toUpperCase()
  } catch {
    // Not a link; it's the code itself.
  }
  return trimmed.toUpperCase()
}

const verified = new Set<string>()

/**
 * Same as TripMembershipService.ensureMembership: content listeners fail if the
 * person's members/{uid} doc is missing, so make sure it's there first.
 */
export async function ensureMembership(tripId: string, uid: string, role: 'owner' | 'member'): Promise<void> {
  const key = `${tripId}-${uid}`
  if (verified.has(key)) return
  const ref = doc(db, 'trips', tripId, 'members', uid)
  const snapshot = await getDoc(ref)
  if (!snapshot.exists()) {
    await setDoc(ref, { uid, role, joinedAt: serverTimestamp() })
    await setDoc(doc(db, 'users', uid), { memberOfTripIDs: arrayUnion(tripId) }, { merge: true })
  }
  verified.add(key)
}

// MARK: Activities (ActivityDTO)

export interface ActivityInput {
  title: string
  location: string
  date: Date
  activityDescription: string
  iconName: string
  /** null clears the cost. */
  cost: number | null
  costCurrency: string
  costNote: string
  /** Only when costCurrency isn't the trip's. */
  exchangeRateToTripCurrency: number | null
  split: SplitInput
}

export async function addActivity(tripId: string, input: ActivityInput, createdBy?: string): Promise<string> {
  const id = newId()
  await setDoc(
    itemRef(tripId, 'activities', id),
    defined({
      ...splitFieldsForCreate(input.split),
      exchangeRateToTripCurrency: input.exchangeRateToTripCurrency ?? undefined,
      createdBy,
      title: input.title,
      activityDescription: input.activityDescription,
      location: input.location,
      date: input.date,
      iconName: input.iconName,
      cost: input.cost ?? undefined,
      costCurrency: input.cost === null ? undefined : input.costCurrency,
      costNote: input.costNote || undefined,
    }),
  )
  return id
}

export async function updateActivity(tripId: string, id: string, input: ActivityInput, locationChanged: boolean): Promise<void> {
  const fields: Record<string, unknown | FieldValue> = {
    title: input.title,
    activityDescription: input.activityDescription,
    location: input.location,
    date: input.date,
    iconName: input.iconName,
    cost: input.cost ?? deleteField(),
    costCurrency: input.cost === null ? deleteField() : input.costCurrency,
    costNote: input.costNote || deleteField(),
    exchangeRateToTripCurrency: input.exchangeRateToTripCurrency ?? deleteField(),
    ...splitFieldsForUpdate(input.split),
  }
  if (locationChanged) {
    fields.latitude = deleteField()
    fields.longitude = deleteField()
    fields.placeID = deleteField()
  }
  await updateDoc(itemRef(tripId, 'activities', id), fields)
}

// MARK: Stays (AccommodationDTO)

export interface StayInput {
  name: string
  type: StayType
  location: string
  numberOfRooms: number
  totalCost: number
  checkInTime: string
  checkOutTime: string
  startDate: Date
  endDate: Date
  split: SplitInput
}

export async function addStay(tripId: string, input: StayInput): Promise<void> {
  const { split, ...fields } = input
  await setDoc(itemRef(tripId, 'accommodations', newId()), { ...fields, ...splitFieldsForCreate(split) })
}

export async function updateStay(tripId: string, id: string, input: StayInput, locationChanged: boolean): Promise<void> {
  const { split, ...fields } = input
  await updateDoc(itemRef(tripId, 'accommodations', id), {
    ...fields,
    ...splitFieldsForUpdate(split),
    ...(locationChanged ? { latitude: deleteField(), longitude: deleteField() } : {}),
  })
}

// MARK: Transport (TransportSegmentDTO)

export interface TransportInput {
  mode: TransportMode
  departureLocation: string
  /** Local midnight, as the app saves it. */
  departureDate: Date
  departureTime: string
  arrivalLocation: string
  arrivalDate: Date | null
  arrivalTime: string | null
  bookingRef: string
  seatNumber: string
  notes: string
  cost: number
  currency: string
  exchangeRateToTripCurrency: number | null
  split: SplitInput
}

export async function addTransport(tripId: string, input: TransportInput): Promise<void> {
  const { split, ...fields } = input
  await setDoc(
    itemRef(tripId, 'transportSegments', newId()),
    defined({
      ...fields,
      ...splitFieldsForCreate(split),
      exchangeRateToTripCurrency: input.exchangeRateToTripCurrency ?? undefined,
      arrivalDate: input.arrivalDate ?? undefined,
      arrivalTime: input.arrivalTime ?? undefined,
      bookingRef: input.bookingRef || undefined,
      seatNumber: input.seatNumber || undefined,
      notes: input.notes || undefined,
    }),
  )
}

export async function updateTransport(
  tripId: string,
  id: string,
  input: TransportInput,
  changed: { from: boolean; to: boolean },
): Promise<void> {
  const { split, ...fields } = input
  await updateDoc(itemRef(tripId, 'transportSegments', id), {
    ...fields,
    ...splitFieldsForUpdate(split),
    exchangeRateToTripCurrency: input.exchangeRateToTripCurrency ?? deleteField(),
    arrivalDate: input.arrivalDate ?? deleteField(),
    arrivalTime: input.arrivalTime ?? deleteField(),
    bookingRef: input.bookingRef || deleteField(),
    seatNumber: input.seatNumber || deleteField(),
    notes: input.notes || deleteField(),
    ...(changed.from ? { departureLatitude: deleteField(), departureLongitude: deleteField() } : {}),
    ...(changed.to ? { arrivalLatitude: deleteField(), arrivalLongitude: deleteField() } : {}),
  })
}

// MARK: Day notes (DayNoteDTO)

export interface DayNoteInput {
  /** Local midnight. */
  day: Date
  title: string
  content: string
}

export async function saveDayNote(tripId: string, id: string | null, input: DayNoteInput): Promise<void> {
  if (id) await updateDoc(itemRef(tripId, 'dayNotes', id), { ...input })
  else await setDoc(itemRef(tripId, 'dayNotes', newId()), { ...input })
}

// MARK: Deleting

export type TripItemCollection =
  | 'activities' | 'accommodations' | 'transportSegments' | 'dayNotes'
  | 'budgetCategories' | 'expenses' | 'settlements' | 'preparationTasks' | 'polls' | 'ideas'

export async function deleteItem(tripId: string, sub: TripItemCollection, id: string): Promise<void> {
  await deleteDoc(itemRef(tripId, sub, id))
}

// MARK: Budget (BudgetCategoryDTO, ExpenseDTO, SettlementDTO)

/**
 * The trip's overall budget is always the sum of its categories
 * (TripMembershipService.syncOverallBudget), so recompute it after each change.
 */
async function syncOverallBudget(tripId: string, total: number): Promise<void> {
  await updateDoc(tripRef(tripId), { overallBudget: total, updatedAt: serverTimestamp() })
}

export async function saveBudgetCategory(tripId: string, id: string | null, input: { name: string; amount: number }, newTotal: number): Promise<void> {
  if (id) await updateDoc(itemRef(tripId, 'budgetCategories', id), { ...input })
  else await setDoc(itemRef(tripId, 'budgetCategories', newId()), { ...input })
  await syncOverallBudget(tripId, newTotal)
}

export async function deleteBudgetCategory(tripId: string, id: string, newTotal: number): Promise<void> {
  await deleteDoc(itemRef(tripId, 'budgetCategories', id))
  await syncOverallBudget(tripId, newTotal)
}

/** A member's individual budget; 0 removes it. */
export async function setMemberBudget(tripId: string, uid: string, amount: number): Promise<void> {
  await updateDoc(tripRef(tripId), { [`memberBudgets.${uid}`]: amount > 0 ? amount : deleteField(), updatedAt: serverTimestamp() })
}

export interface ExpenseInput {
  name: string
  date: Date | null
  time: string | null
  cost: number
  costCurrency: string
  exchangeRateToTripCurrency: number | null
  split: SplitInput
}

export async function saveExpense(tripId: string, existing: Expense | undefined, input: ExpenseInput): Promise<void> {
  if (existing) {
    await updateDoc(itemRef(tripId, 'expenses', existing.id), {
      name: input.name,
      date: input.date ?? deleteField(),
      time: input.time ?? deleteField(),
      cost: input.cost,
      costCurrency: input.costCurrency,
      exchangeRateToTripCurrency: input.exchangeRateToTripCurrency ?? deleteField(),
      ...splitFieldsForUpdate(input.split),
    })
  } else {
    await setDoc(
      itemRef(tripId, 'expenses', newId()),
      defined({
        name: input.name,
        date: input.date ?? undefined,
        time: input.time ?? undefined,
        cost: input.cost,
        costCurrency: input.costCurrency,
        exchangeRateToTripCurrency: input.exchangeRateToTripCurrency ?? undefined,
        ...splitFieldsForCreate(input.split),
      }),
    )
  }
}

export async function recordSettlement(tripId: string, input: { fromUID: string; toUID: string; amount: number }): Promise<void> {
  await setDoc(itemRef(tripId, 'settlements', newId()), { ...input, date: new Date() })
}

// MARK: Preparation (PreparationTaskDTO)

export interface PrepTaskInput {
  name: string
  category: string
  notes: string
  completed: boolean
}

export async function savePrepTask(tripId: string, id: string | null, input: PrepTaskInput): Promise<void> {
  if (id) await updateDoc(itemRef(tripId, 'preparationTasks', id), { ...input })
  else await setDoc(itemRef(tripId, 'preparationTasks', newId()), { ...input })
}

export async function setPrepTaskCompleted(tripId: string, id: string, completed: boolean): Promise<void> {
  await updateDoc(itemRef(tripId, 'preparationTasks', id), { completed })
}

// MARK: Polls (TripPollDTO, TripPollService)

export interface PollInput {
  kind: 'question' | 'activityProposal'
  question: string
  options: string[]
  location: string
  proposedDate: Date | null
  iconName: string
}

export async function createPoll(tripId: string, uid: string, input: PollInput): Promise<void> {
  const proposal = input.kind === 'activityProposal'
  await setDoc(
    itemRef(tripId, 'polls', newId()),
    defined({
      kind: input.kind,
      question: input.question,
      options: proposal ? ['Yes', 'No'] : input.options,
      votes: {},
      createdByUID: uid,
      createdAt: new Date(),
      isClosed: false,
      location: proposal ? input.location : '',
      iconName: input.iconName,
      proposedDate: proposal && input.proposedDate ? input.proposedDate : undefined,
    }),
  )
}

/** Casts or changes a vote, or takes it back when it's the option already chosen. Field-level, so votes never collide. */
export async function vote(tripId: string, poll: Poll, option: number, uid: string): Promise<void> {
  if (poll.isClosed) return
  await updateDoc(itemRef(tripId, 'polls', poll.id), { [`votes.${uid}`]: poll.votes[uid] === option ? deleteField() : option })
}

export async function closePoll(tripId: string, pollId: string): Promise<void> {
  await updateDoc(itemRef(tripId, 'polls', pollId), { isClosed: true })
}

/** Adds the proposed activity to the itinerary and closes the vote (TripPollService.approve). */
export async function approvePoll(tripId: string, poll: Poll, tripStart: Date, uid: string): Promise<void> {
  await addActivityFrom(tripId, uid, {
    title: poll.question,
    location: poll.location,
    latitude: poll.latitude,
    longitude: poll.longitude,
    date: poll.proposedDate ?? tripStart,
    iconName: poll.iconName,
    description: '',
  })
  await closePoll(tripId, poll.id)
}

async function addActivityFrom(
  tripId: string,
  uid: string,
  a: { title: string; location: string; latitude: number | null; longitude: number | null; date: Date; iconName: string; description: string },
): Promise<void> {
  await setDoc(
    itemRef(tripId, 'activities', newId()),
    defined({
      title: a.title,
      activityDescription: a.description,
      location: a.location,
      latitude: a.latitude ?? undefined,
      longitude: a.longitude ?? undefined,
      date: a.date,
      iconName: a.iconName,
      splitUIDs: [],
      createdBy: uid,
    }),
  )
}

// MARK: Ideas (TripIdeaDTO, TripIdeaService)

export interface IdeaInput {
  title: string
  note: string
  location: string
  link: string
}

export async function createIdea(tripId: string, uid: string, input: IdeaInput): Promise<void> {
  await setDoc(itemRef(tripId, 'ideas', newId()), {
    ...input,
    addedByUID: uid,
    createdAt: new Date(),
    likedBy: [],
    isPlanned: false,
  })
}

export async function updateIdea(tripId: string, idea: Idea, input: IdeaInput): Promise<void> {
  await updateDoc(itemRef(tripId, 'ideas', idea.id), {
    ...input,
    ...(input.location !== idea.location ? { latitude: deleteField(), longitude: deleteField() } : {}),
  })
}

export async function toggleIdeaLike(tripId: string, idea: Idea, uid: string): Promise<void> {
  await updateDoc(itemRef(tripId, 'ideas', idea.id), { likedBy: idea.likedBy.includes(uid) ? arrayRemove(uid) : arrayUnion(uid) })
}

/** Adds the idea to the itinerary an hour after the latest activity, and marks it planned. */
export async function planIdea(tripId: string, idea: Idea, activities: Activity[], trip: { startDate: Date; endDate: Date }, uid: string): Promise<void> {
  const latest = activities.reduce<number | null>((max, a) => (max === null || a.date.getTime() > max ? a.date.getTime() : max), null)
  const lastMoment = new Date(trip.endDate)
  lastMoment.setHours(23, 59, 0, 0)
  const date = latest === null ? trip.startDate : new Date(Math.min(latest + 60 * 60 * 1000, lastMoment.getTime()))
  await addActivityFrom(tripId, uid, {
    title: idea.title,
    location: idea.location,
    latitude: idea.latitude,
    longitude: idea.longitude,
    date,
    iconName: 'mappin.and.ellipse',
    description: idea.note,
  })
  await updateDoc(itemRef(tripId, 'ideas', idea.id), { isPlanned: true })
}

// MARK: Members and deleting a trip

/**
 * Takes a removed member out of every cost split (TripMembershipService.removeFromSplits):
 * custom amounts no longer add up without them, so those go back to an even split.
 */
export async function removeFromSplits(
  tripId: string,
  uid: string,
  items: { activities: CostSplit[]; stays: CostSplit[]; transport: CostSplit[]; expenses: CostSplit[] },
): Promise<void> {
  const groups: [string, (CostSplit & { id: string })[]][] = [
    ['activities', items.activities as (CostSplit & { id: string })[]],
    ['accommodations', items.stays as (CostSplit & { id: string })[]],
    ['transportSegments', items.transport as (CostSplit & { id: string })[]],
    ['expenses', items.expenses as (CostSplit & { id: string })[]],
  ]
  for (const [sub, list] of groups) {
    for (const item of list.filter((i) => i.splitUIDs.includes(uid))) {
      await updateDoc(itemRef(tripId, sub, item.id), { splitUIDs: item.splitUIDs.filter((u) => u !== uid), splitAmounts: deleteField() })
    }
  }
}

/** The owner removing someone, or a member leaving (TripMembershipService.removeMember). */
export async function removeMember(tripId: string, uid: string): Promise<void> {
  await deleteDoc(doc(db, 'trips', tripId, 'members', uid))
  try {
    await setDoc(doc(db, 'users', uid), { memberOfTripIDs: arrayRemove(tripId) }, { merge: true })
  } catch {
    // The rules may not let one person edit another's user doc; the app ignores this too.
  }
}

/** Members last: the rules check membership while everything else is deleted. */
const tripSubcollections = [
  'liveLocations', 'activities', 'accommodations', 'budgetCategories',
  'preparationTasks', 'transportSegments', 'dayNotes', 'settlements', 'expenses', 'polls', 'ideas', 'members',
]

/** Same as TripMembershipService.deleteTripRecord: each step on its own so one failure can't block the rest. */
export async function deleteTrip(tripId: string, uid: string): Promise<void> {
  const snapshot = await getDoc(tripRef(tripId))
  const code = snapshot.data()?.joinCode
  if (typeof code === 'string') await deleteDoc(doc(db, 'tripJoinCodes', code)).catch(() => {})
  for (const name of tripSubcollections) {
    try {
      const docs = await getDocs(collection(db, 'trips', tripId, name))
      const refs = docs.docs.map((d) => d.ref)
      for (let i = 0; i < refs.length; i += 400) {
        const batch = writeBatch(db)
        refs.slice(i, i + 400).forEach((ref) => batch.delete(ref))
        await batch.commit()
      }
    } catch {
      // Keep going, as the app does.
    }
  }
  await deleteDoc(tripRef(tripId))
  await setDoc(doc(db, 'users', uid), { memberOfTripIDs: arrayRemove(tripId) }, { merge: true }).catch(() => {})
}

export type { Stay, Transport }
