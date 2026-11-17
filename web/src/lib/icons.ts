import type { Component } from 'vue'
import {
  PhAirplane, PhAirplaneLanding, PhAirplaneTakeoff, PhBed, PhBicycle, PhBoat, PhBuildings, PhBus,
  PhCake, PhCalendar, PhCamera, PhCar, PhClock, PhCloudRain, PhCoffee, PhCreditCard, PhFlag,
  PhForkKnife, PhGameController, PhGasPump, PhHouse, PhLetterCircleP, PhListChecks, PhMapPin,
  PhMapTrifold, PhMaskHappy, PhMoney, PhMotorcycle, PhMusicNote, PhPersonSimpleHike,
  PhPersonSimpleWalk, PhQuestion, PhSailboat, PhSnowflake, PhStar, PhSun, PhTaxi, PhTent, PhTicket,
  PhTrain, PhTram, PhTruck, PhUsers, PhUsersThree, PhVan, PhWallet, PhWine,
} from '@phosphor-icons/vue'
import type { TransportMode } from './model'

/**
 * The app stores SF Symbol names (ActivityIconLibrary.swift). These are the
 * closest Phosphor icons, in the same groups as the app's picker.
 */
export const activityIcons: { name: string; icons: { symbol: string; icon: Component }[] }[] = [
  { name: 'Travel', icons: [
    { symbol: 'airplane', icon: PhAirplane }, { symbol: 'airplane.departure', icon: PhAirplaneTakeoff },
    { symbol: 'airplane.arrival', icon: PhAirplaneLanding }, { symbol: 'car', icon: PhCar },
    { symbol: 'bicycle', icon: PhBicycle }, { symbol: 'figure.walk', icon: PhPersonSimpleWalk },
  ] },
  { name: 'Transport', icons: [
    { symbol: 'bus', icon: PhBus }, { symbol: 'tram', icon: PhTram }, { symbol: 'ferry', icon: PhBoat },
    { symbol: 'fuelpump', icon: PhGasPump }, { symbol: 'parkingsign.circle', icon: PhLetterCircleP },
  ] },
  { name: 'Accommodation', icons: [
    { symbol: 'bed.double', icon: PhBed }, { symbol: 'house', icon: PhHouse },
    { symbol: 'building.2', icon: PhBuildings }, { symbol: 'tent', icon: PhTent },
  ] },
  { name: 'Food', icons: [
    { symbol: 'fork.knife', icon: PhForkKnife }, { symbol: 'cup.and.saucer', icon: PhCoffee },
    { symbol: 'wineglass', icon: PhWine }, { symbol: 'birthday.cake', icon: PhCake },
  ] },
  { name: 'Fun', icons: [
    { symbol: 'figure.walk.motion', icon: PhPersonSimpleHike }, { symbol: 'camera', icon: PhCamera },
    { symbol: 'ticket', icon: PhTicket }, { symbol: 'gamecontroller', icon: PhGameController },
    { symbol: 'music.note', icon: PhMusicNote }, { symbol: 'theatermasks', icon: PhMaskHappy },
  ] },
  { name: 'Planning', icons: [
    { symbol: 'calendar', icon: PhCalendar }, { symbol: 'checklist', icon: PhListChecks },
    { symbol: 'clock', icon: PhClock }, { symbol: 'map', icon: PhMapTrifold },
  ] },
  { name: 'Social', icons: [{ symbol: 'person.2', icon: PhUsers }, { symbol: 'person.3', icon: PhUsersThree }] },
  { name: 'Weather', icons: [
    { symbol: 'sun.max', icon: PhSun }, { symbol: 'cloud.rain', icon: PhCloudRain }, { symbol: 'snowflake', icon: PhSnowflake },
  ] },
  { name: 'Budgeting', icons: [
    { symbol: 'banknote', icon: PhMoney }, { symbol: 'creditcard', icon: PhCreditCard }, { symbol: 'wallet.pass', icon: PhWallet },
  ] },
  { name: 'Misc', icons: [
    { symbol: 'mappin.and.ellipse', icon: PhMapPin }, { symbol: 'star', icon: PhStar },
    { symbol: 'flag', icon: PhFlag }, { symbol: 'questionmark.circle', icon: PhQuestion },
  ] },
]

const bySymbol: Record<string, Component> = Object.fromEntries(
  activityIcons.flatMap((group) => group.icons.map((item) => [item.symbol, item.icon])),
)

/** Any SF Symbol name to a Phosphor icon; unknown names (e.g. from Claude) get a map pin. */
export function iconFor(symbol: string): Component {
  return bySymbol[symbol] ?? PhMapPin
}

export const transportIcons: Record<TransportMode, Component> = {
  flight: PhAirplane,
  bus: PhBus,
  jeepney: PhTruck,
  van: PhVan,
  train: PhTrain,
  ferry: PhBoat,
  bangka: PhSailboat,
  car: PhCar,
  rideshare: PhTaxi,
  tricycle: PhMotorcycle,
  motorcycle: PhMotorcycle,
  pedicab: PhBicycle,
  other: PhMapPin,
}
