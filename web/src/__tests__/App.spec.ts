import { describe, it, expect } from 'vitest'
import { combine, fromDateInput, tripDays, tripStatus } from '@/lib/dates'
import { extractJoinCode, joinCode, newId } from '@/lib/writes'

describe('dates', () => {
  it('lists every day of a trip', () => {
    const days = tripDays(new Date(2026, 10, 16, 15), new Date(2026, 10, 18, 9))
    expect(days.map((d) => d.getDate())).toEqual([16, 17, 18])
  })

  it('combines a day and an HH:mm time in local time', () => {
    const when = combine(fromDateInput('2026-12-10'), '09:30')
    expect([when.getFullYear(), when.getMonth(), when.getDate(), when.getHours(), when.getMinutes()]).toEqual([2026, 11, 10, 9, 30])
  })

  it('describes where today is in the trip', () => {
    const now = new Date(2026, 10, 17, 12)
    expect(tripStatus(new Date(2026, 10, 16), new Date(2026, 10, 18), now).label).toBe('Active · Day 2 of 3')
    expect(tripStatus(new Date(2026, 10, 18), new Date(2026, 10, 19), now).label).toBe('Tomorrow')
    expect(tripStatus(new Date(2026, 10, 1), new Date(2026, 10, 3), now).kind).toBe('past')
  })
})

describe('ids and codes', () => {
  it('makes upper-case UUIDs like Swift', () => {
    expect(newId()).toMatch(/^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/)
  })

  it('makes join codes from the app’s alphabet', () => {
    expect(joinCode()).toMatch(/^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{6}$/)
  })

  it('reads a join code from a code or an invite link', () => {
    expect(extractJoinCode(' abc234 ')).toBe('ABC234')
    expect(extractJoinCode('https://example.com/join?code=xyz789')).toBe('XYZ789')
  })
})
