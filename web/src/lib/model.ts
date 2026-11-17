import { Timestamp, type DocumentData } from 'firebase/firestore'

/**
 * The Firestore shapes the iPhone app reads and writes (Agdayo/Services/Sync/*Sync.swift
 * and TripMembershipService.swift). The app decodes these into SwiftData, and a field
 * it can't decode can break it, so every write in writes.ts must keep these names and types.
 */

export const tripThemes = ['peach', 'blue', 'amber', 'emerald', 'violet', 'teal', 'rose', 'slate'] as const
export type TripTheme = (typeof tripThemes)[number]

export const stayTypes = ['hotel', 'airbnb', 'transient', 'other'] as const
export type StayType = (typeof stayTypes)[number]
export const stayTypeNames: Record<StayType, string> = {
  hotel: 'Hotel',
  airbnb: 'Airbnb',
  transient: 'Transient',
  other: 'Other',
}

/** TransportMode raw values in the app. */
export const transportModes = [
  'flight', 'bus', 'jeepney', 'van', 'train', 'ferry', 'bangka',
  'car', 'rideshare', 'tricycle', 'motorcycle', 'pedicab', 'other',
] as const
export type TransportMode = (typeof transportModes)[number]
export const transportModeNames: Record<TransportMode, string> = {
  flight: 'Flight',
  bus: 'Bus',
  jeepney: 'Jeepney',
  van: 'Van/UV Express',
  train: 'Train',
  ferry: 'Ferry',
  bangka: 'Bangka',
  car: 'Car',
  rideshare: 'Taxi/Ride-share',
  tricycle: 'Tricycle',
  motorcycle: 'Motorcycle Taxi',
  pedicab: 'Pedicab',
  other: 'Other',
}

export interface Trip {
  id: string
  ownerUID: string | null
  name: string
  location: string
  theme: TripTheme
  startDate: Date
  endDate: Date
  overallBudget: number
  currency: string
  tripDescription: string
  joinCode: string | null
  latitude: number | null
  longitude: number | null
  /** Missing on trips made while the app was paid; those owners count as unlocked. */
  ownerUnlocked: boolean | null
  /** Individual budgets, uid -> amount in the trip currency. */
  memberBudgets: Record<string, number>
}

/** Who paid and who shares a cost (ExpenseSplitSection in the app). */
export interface CostSplit {
  paidByUID: string | null
  splitUIDs: string[]
  /** Custom per-person amounts in the item's own currency; empty means split evenly. */
  splitAmounts: Record<string, number>
  budgetCategoryID: string | null
  budgetMemberUID: string | null
}

export interface Activity extends CostSplit {
  id: string
  title: string
  activityDescription: string
  location: string
  latitude: number | null
  longitude: number | null
  date: Date
  cost: number | null
  costCurrency: string | null
  costNote: string | null
  exchangeRateToTripCurrency: number | null
  iconName: string
  createdBy: string | null
}

export interface Stay extends CostSplit {
  id: string
  name: string
  type: StayType
  location: string
  latitude: number | null
  longitude: number | null
  numberOfRooms: number
  totalCost: number
  checkInTime: string
  checkOutTime: string
  startDate: Date
  endDate: Date
}

export interface Transport extends CostSplit {
  id: string
  mode: TransportMode
  departureLocation: string
  /** Local midnight of the departure day; the time is in departureTime ("HH:mm"). */
  departureDate: Date
  departureTime: string
  arrivalLocation: string
  arrivalDate: Date | null
  arrivalTime: string | null
  bookingRef: string | null
  seatNumber: string | null
  cost: number
  currency: string
  exchangeRateToTripCurrency: number | null
  notes: string | null
}

export interface DayNote {
  id: string
  /** Local midnight of the day. */
  day: Date
  title: string
  content: string
}

export interface BudgetCategory {
  id: string
  name: string
  amount: number
}

export interface Expense extends CostSplit {
  id: string
  name: string
  date: Date | null
  /** "HH:mm", only with a date. */
  time: string | null
  cost: number
  costCurrency: string | null
  exchangeRateToTripCurrency: number | null
}

/** A payment one member really made to another (Settlement in the app). */
export interface Settlement {
  id: string
  fromUID: string
  toUID: string
  amount: number
  date: Date
}

export const prepCategories = ['Documents', 'Packing', 'Essentials', 'Transportation', 'Health', 'Finance', 'Electronics'] as const

export interface PrepTask {
  id: string
  name: string
  category: string
  notes: string
  completed: boolean
}

export type PollKind = 'question' | 'activityProposal'

export interface Poll {
  id: string
  kind: PollKind
  question: string
  options: string[]
  /** uid -> option index */
  votes: Record<string, number>
  createdByUID: string
  createdAt: Date
  isClosed: boolean
  location: string
  latitude: number | null
  longitude: number | null
  iconName: string
  proposedDate: Date | null
}

export interface Idea {
  id: string
  title: string
  note: string
  location: string
  latitude: number | null
  longitude: number | null
  link: string
  addedByUID: string
  createdAt: Date
  likedBy: string[]
  isPlanned: boolean
}

export interface Member {
  uid: string
  role: string
}

export interface UserProfile {
  uid: string
  displayName: string
  email: string
  photoURL: string | null
  memberOfTripIDs: string[]
  /** Set by the Worker after it checks an App Store purchase. Not writable by clients. */
  unlocked: boolean
}

// MARK: Reading

function date(value: unknown): Date | null {
  if (value instanceof Timestamp) return value.toDate()
  if (value instanceof Date) return value
  if (typeof value === 'string' || typeof value === 'number') {
    const parsed = new Date(value)
    return Number.isNaN(parsed.getTime()) ? null : parsed
  }
  return null
}

const str = (value: unknown, fallback = ''): string => (typeof value === 'string' ? value : fallback)
const optStr = (value: unknown): string | null => (typeof value === 'string' ? value : null)
const num = (value: unknown, fallback = 0): number => (typeof value === 'number' && Number.isFinite(value) ? value : fallback)
const optNum = (value: unknown): number | null => (typeof value === 'number' && Number.isFinite(value) ? value : null)

const strList = (value: unknown): string[] => (Array.isArray(value) ? value.filter((x): x is string => typeof x === 'string') : [])
function numMap(value: unknown): Record<string, number> {
  if (!value || typeof value !== 'object') return {}
  return Object.fromEntries(Object.entries(value as Record<string, unknown>).filter(([, v]) => typeof v === 'number' && Number.isFinite(v))) as Record<string, number>
}

function costSplit(d: DocumentData): CostSplit {
  return {
    paidByUID: optStr(d.paidByUID),
    splitUIDs: strList(d.splitUIDs),
    splitAmounts: numMap(d.splitAmounts),
    budgetCategoryID: optStr(d.budgetCategoryID),
    budgetMemberUID: optStr(d.budgetMemberUID),
  }
}

function oneOf<T extends string>(options: readonly T[], value: unknown, fallback: T): T {
  return options.includes(value as T) ? (value as T) : fallback
}

/** Returns null for documents the app itself couldn't decode either (missing required fields). */
export function toTrip(id: string, d: DocumentData): Trip | null {
  const startDate = date(d.startDate)
  const endDate = date(d.endDate)
  if (!startDate || !endDate || typeof d.name !== 'string') return null
  return {
    id,
    ownerUID: optStr(d.ownerUID),
    name: d.name,
    location: str(d.location),
    theme: oneOf(tripThemes, d.theme, 'peach'),
    startDate,
    endDate,
    overallBudget: num(d.overallBudget),
    currency: str(d.currency, 'PHP'),
    tripDescription: str(d.tripDescription),
    joinCode: optStr(d.joinCode),
    latitude: optNum(d.latitude),
    longitude: optNum(d.longitude),
    ownerUnlocked: typeof d.ownerUnlocked === 'boolean' ? d.ownerUnlocked : null,
    memberBudgets: numMap(d.memberBudgets),
  }
}

export function toActivity(id: string, d: DocumentData): Activity | null {
  const when = date(d.date)
  if (!when || typeof d.title !== 'string') return null
  return {
    id,
    title: d.title,
    activityDescription: str(d.activityDescription),
    location: str(d.location),
    latitude: optNum(d.latitude),
    longitude: optNum(d.longitude),
    date: when,
    cost: optNum(d.cost),
    costCurrency: optStr(d.costCurrency),
    costNote: optStr(d.costNote),
    exchangeRateToTripCurrency: optNum(d.exchangeRateToTripCurrency),
    iconName: str(d.iconName, 'mappin.and.ellipse'),
    createdBy: optStr(d.createdBy),
    ...costSplit(d),
  }
}

export function toStay(id: string, d: DocumentData): Stay | null {
  const startDate = date(d.startDate)
  const endDate = date(d.endDate)
  if (!startDate || !endDate || typeof d.name !== 'string') return null
  return {
    id,
    name: d.name,
    type: oneOf(stayTypes, d.type, 'other'),
    location: str(d.location),
    latitude: optNum(d.latitude),
    longitude: optNum(d.longitude),
    numberOfRooms: num(d.numberOfRooms, 1),
    totalCost: num(d.totalCost),
    checkInTime: str(d.checkInTime, '15:00'),
    checkOutTime: str(d.checkOutTime, '11:00'),
    startDate,
    endDate,
    ...costSplit(d),
  }
}

export function toTransport(id: string, d: DocumentData): Transport | null {
  const departureDate = date(d.departureDate)
  if (!departureDate || typeof d.departureLocation !== 'string') return null
  return {
    id,
    mode: oneOf(transportModes, d.mode, 'other'),
    departureLocation: d.departureLocation,
    departureDate,
    departureTime: str(d.departureTime, '00:00'),
    arrivalLocation: str(d.arrivalLocation),
    arrivalDate: date(d.arrivalDate),
    arrivalTime: optStr(d.arrivalTime),
    bookingRef: optStr(d.bookingRef),
    seatNumber: optStr(d.seatNumber),
    cost: num(d.cost),
    currency: str(d.currency, 'PHP'),
    exchangeRateToTripCurrency: optNum(d.exchangeRateToTripCurrency),
    notes: optStr(d.notes),
    ...costSplit(d),
  }
}

export function toDayNote(id: string, d: DocumentData): DayNote | null {
  const day = date(d.day)
  if (!day) return null
  return { id, day, title: str(d.title), content: str(d.content) }
}

export function toBudgetCategory(id: string, d: DocumentData): BudgetCategory | null {
  if (typeof d.name !== 'string') return null
  return { id, name: d.name, amount: num(d.amount) }
}

export function toExpense(id: string, d: DocumentData): Expense | null {
  if (typeof d.name !== 'string') return null
  return {
    id,
    name: d.name,
    date: date(d.date),
    time: optStr(d.time),
    cost: num(d.cost),
    costCurrency: optStr(d.costCurrency),
    exchangeRateToTripCurrency: optNum(d.exchangeRateToTripCurrency),
    ...costSplit(d),
  }
}

export function toSettlement(id: string, d: DocumentData): Settlement | null {
  const when = date(d.date)
  if (!when || typeof d.fromUID !== 'string' || typeof d.toUID !== 'string') return null
  return { id, fromUID: d.fromUID, toUID: d.toUID, amount: num(d.amount), date: when }
}

export function toPrepTask(id: string, d: DocumentData): PrepTask | null {
  if (typeof d.name !== 'string') return null
  return { id, name: d.name, category: str(d.category, 'Other'), notes: str(d.notes), completed: d.completed === true }
}

export function toPoll(id: string, d: DocumentData): Poll | null {
  const createdAt = date(d.createdAt)
  if (!createdAt || typeof d.question !== 'string') return null
  const votes: Record<string, number> = {}
  for (const [uid, option] of Object.entries(numMap(d.votes))) votes[uid] = Math.trunc(option)
  return {
    id,
    kind: d.kind === 'activityProposal' ? 'activityProposal' : 'question',
    question: d.question,
    options: strList(d.options),
    votes,
    createdByUID: str(d.createdByUID),
    createdAt,
    isClosed: d.isClosed === true,
    location: str(d.location),
    latitude: optNum(d.latitude),
    longitude: optNum(d.longitude),
    iconName: str(d.iconName, 'mappin.and.ellipse'),
    proposedDate: date(d.proposedDate),
  }
}

export function toIdea(id: string, d: DocumentData): Idea | null {
  const createdAt = date(d.createdAt)
  if (!createdAt || typeof d.title !== 'string') return null
  return {
    id,
    title: d.title,
    note: str(d.note),
    location: str(d.location),
    latitude: optNum(d.latitude),
    longitude: optNum(d.longitude),
    link: str(d.link),
    addedByUID: str(d.addedByUID),
    createdAt,
    likedBy: strList(d.likedBy),
    isPlanned: d.isPlanned === true,
  }
}

export function toMember(id: string, d: DocumentData): Member {
  return { uid: str(d.uid, id), role: str(d.role, 'member') }
}

export function toUserProfile(uid: string, d: DocumentData | undefined): UserProfile {
  return {
    uid,
    displayName: str(d?.displayName, 'Traveler'),
    email: str(d?.email),
    photoURL: optStr(d?.photoURL),
    memberOfTripIDs: Array.isArray(d?.memberOfTripIDs) ? d.memberOfTripIDs.filter((x: unknown) => typeof x === 'string') : [],
    unlocked: d?.unlocked === true,
  }
}
