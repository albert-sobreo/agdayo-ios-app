import type { User } from 'firebase/auth'
import {
  arrayUnion, collection, deleteDoc, deleteField, doc, getCountFromServer, getDoc, serverTimestamp,
  setDoc, updateDoc, type FieldValue,
} from 'firebase/firestore'
import { db } from '@/firebase'
import type { StayType, TransportMode, TripTheme } from './model'

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
}

export async function addActivity(tripId: string, input: ActivityInput): Promise<void> {
  await setDoc(
    itemRef(tripId, 'activities', newId()),
    defined({
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
}

export async function addStay(tripId: string, input: StayInput): Promise<void> {
  await setDoc(itemRef(tripId, 'accommodations', newId()), { ...input })
}

export async function updateStay(tripId: string, id: string, input: StayInput, locationChanged: boolean): Promise<void> {
  await updateDoc(itemRef(tripId, 'accommodations', id), {
    ...input,
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
}

export async function addTransport(tripId: string, input: TransportInput): Promise<void> {
  await setDoc(
    itemRef(tripId, 'transportSegments', newId()),
    defined({
      ...input,
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
  await updateDoc(itemRef(tripId, 'transportSegments', id), {
    ...input,
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

export type TripItemCollection = 'activities' | 'accommodations' | 'transportSegments' | 'dayNotes'

export async function deleteItem(tripId: string, sub: TripItemCollection, id: string): Promise<void> {
  await deleteDoc(itemRef(tripId, sub, id))
}
