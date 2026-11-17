/**
 * Day and time helpers. Like the iPhone app, times are shown and picked in the
 * browser's own time zone (the app has no per-trip time zone yet).
 */

export function startOfDay(value: Date): Date {
  return new Date(value.getFullYear(), value.getMonth(), value.getDate())
}

export function addDays(value: Date, days: number): Date {
  return new Date(value.getFullYear(), value.getMonth(), value.getDate() + days)
}

export function isSameDay(a: Date, b: Date): boolean {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
}

/** Every calendar day of the trip, first to last. */
export function tripDays(start: Date, end: Date): Date[] {
  const days: Date[] = []
  const last = startOfDay(end)
  for (let day = startOfDay(start); day <= last && days.length < 366; day = addDays(day, 1)) days.push(day)
  return days
}

/** "2026-11-17" for <input type="date">. */
export function toDateInput(value: Date): string {
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${value.getFullYear()}-${pad(value.getMonth() + 1)}-${pad(value.getDate())}`
}

/** "09:30" for <input type="time">. */
export function toTimeInput(value: Date): string {
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${pad(value.getHours())}:${pad(value.getMinutes())}`
}

/** Local midnight of a "2026-11-17" input value. */
export function fromDateInput(value: string): Date {
  const [y, m, d] = value.split('-').map(Number)
  return new Date(y ?? 1970, (m ?? 1) - 1, d ?? 1)
}

/** A local date and "HH:mm" combined. */
export function combine(day: Date, time: string): Date {
  const [h, m] = time.split(':').map(Number)
  return new Date(day.getFullYear(), day.getMonth(), day.getDate(), h ?? 0, m ?? 0)
}

export const isTime = (value: string) => /^([01]\d|2[0-3]):[0-5]\d$/.test(value)

const dayFormat = new Intl.DateTimeFormat(undefined, { weekday: 'short', month: 'short', day: 'numeric' })
const shortFormat = new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' })
const timeFormat = new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' })

export const formatDay = (value: Date) => dayFormat.format(value)
export const formatShort = (value: Date) => shortFormat.format(value)
export const formatTime = (value: Date) => timeFormat.format(value)
/** "15:00" shown as the browser's usual time format, e.g. "3:00 PM". */
export const formatHHmm = (value: string) => (isTime(value) ? timeFormat.format(combine(new Date(), value)) : value)

export function formatRange(start: Date, end: Date): string {
  const sameYear = start.getFullYear() === end.getFullYear()
  const endText = new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric', year: 'numeric' }).format(end)
  if (isSameDay(start, end)) return endText
  return `${sameYear ? shortFormat.format(start) : new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' }).format(start)} – ${endText}`
}

export function formatMoney(amount: number, currency: string): string {
  try {
    return new Intl.NumberFormat(undefined, { style: 'currency', currency, maximumFractionDigits: 2 }).format(amount)
  } catch {
    return `${currency} ${amount.toFixed(2)}`
  }
}

/** Where today sits relative to the trip. */
export function tripStatus(start: Date, end: Date, now = new Date()): { label: string; kind: 'upcoming' | 'active' | 'past' } {
  const today = startOfDay(now)
  const first = startOfDay(start)
  const last = startOfDay(end)
  if (today < first) {
    const days = Math.round((first.getTime() - today.getTime()) / 86_400_000)
    return { label: days === 1 ? 'Tomorrow' : `In ${days} days`, kind: 'upcoming' }
  }
  if (today > last) return { label: 'Done', kind: 'past' }
  const day = Math.round((today.getTime() - first.getTime()) / 86_400_000) + 1
  const total = Math.round((last.getTime() - first.getTime()) / 86_400_000) + 1
  return { label: `Active · Day ${day} of ${total}`, kind: 'active' }
}
