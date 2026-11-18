import { auth } from '@/firebase'
import { config } from '@/config'

/**
 * Apple MapKit JS, the same maps as the iPhone app. The script loads once, and
 * MapKit asks our Worker (GET /v1/mapkit-token) for a short-lived token,
 * signed with the MapKit JS key kept in the Worker's secrets.
 */

export interface Coordinate {
  latitude: number
  longitude: number
}

/* Only the parts of MapKit JS the web uses. */
export type MKCoordinate = Coordinate
export interface MKAnnotation {
  coordinate: MKCoordinate
  data: Record<string, unknown>
  selected: boolean
  addEventListener(type: 'select' | 'deselect', listener: () => void): void
}
export interface MKOverlay {
  data?: Record<string, unknown>
}
export interface MKMap {
  colorScheme: string
  showsCompass: string
  annotations: MKAnnotation[]
  overlays: MKOverlay[]
  addAnnotations(list: MKAnnotation[]): void
  removeAnnotations(list: MKAnnotation[]): void
  addOverlays(list: MKOverlay[]): void
  removeOverlays(list: MKOverlay[]): void
  showItems(items: (MKAnnotation | MKOverlay)[], options?: { animate?: boolean; padding?: unknown; minimumSpan?: unknown }): void
  setCenterAnimated(coordinate: MKCoordinate, animate?: boolean): void
  setRegionAnimated(region: unknown, animate?: boolean): void
  destroy(): void
}
interface MKSearchPlace {
  coordinate: MKCoordinate
}
export interface MapKit {
  init(options: { authorizationCallback: (done: (token: string) => void) => void; language?: string }): void
  Map: new (element: HTMLElement, options?: Record<string, unknown>) => MKMap
  Coordinate: new (latitude: number, longitude: number) => MKCoordinate
  CoordinateSpan: new (latitudeDelta: number, longitudeDelta: number) => unknown
  CoordinateRegion: new (center: MKCoordinate, span: unknown) => unknown
  Padding: new (top: number, right: number, bottom: number, left: number) => unknown
  MarkerAnnotation: new (coordinate: MKCoordinate, options?: Record<string, unknown>) => MKAnnotation
  PolylineOverlay: new (points: MKCoordinate[], options?: Record<string, unknown>) => MKOverlay
  Style: new (options: Record<string, unknown>) => unknown
  Search: new (options?: Record<string, unknown>) => {
    search(query: string, callback: (error: unknown, data: { places: MKSearchPlace[] }) => void, options?: Record<string, unknown>): void
  }
  addEventListener(type: 'error', listener: (event: { status: string }) => void): void
}

declare global {
  interface Window {
    mapkit?: MapKit
  }
}

let loading: Promise<MapKit> | null = null

async function fetchToken(): Promise<string> {
  const idToken = await auth.currentUser?.getIdToken()
  if (!idToken) throw new Error('Sign in to see the map.')
  const response = await fetch(`${config.workerUrl.replace(/\/+$/, '')}/v1/mapkit-token`, {
    headers: { authorization: `Bearer ${idToken}` },
  })
  const body = (await response.json().catch(() => ({}))) as { token?: string; error?: string }
  if (!response.ok || !body.token) throw new Error(body.error || 'The map couldn’t load.')
  return body.token
}

export function loadMapKit(): Promise<MapKit> {
  if (loading) return loading
  loading = new Promise<MapKit>((resolve, reject) => {
    const script = document.createElement('script')
    script.src = 'https://cdn.apple-mapkit.com/mk/5.x.x/mapkit.core.js'
    script.crossOrigin = 'anonymous'
    script.async = true
    script.dataset.libraries = 'map,annotations,overlays,services'
    script.dataset.callback = '__agdayoMapKitLoaded'
    ;(window as unknown as Record<string, unknown>).__agdayoMapKitLoaded = () => {
      const mapkit = window.mapkit
      if (!mapkit) return reject(new Error('The map couldn’t load.'))
      mapkit.init({
        authorizationCallback: (done) => {
          fetchToken().then(done, (err) => console.warn('MapKit token', err))
        },
        language: navigator.language,
      })
      resolve(mapkit)
    }
    script.onerror = () => {
      loading = null
      reject(new Error('The map couldn’t load. Check your connection.'))
    }
    document.head.appendChild(script)
  })
  return loading
}

const geocoded = new Map<string, Coordinate | null>()

/**
 * Finds a place typed as text (MapKit search, near the trip's area when known),
 * like the app does for places without a pin. Remembered for this visit only.
 */
export function geocode(mapkit: MapKit, query: string, near: Coordinate | null): Promise<Coordinate | null> {
  const key = `${query}|${near?.latitude ?? ''}|${near?.longitude ?? ''}`
  if (geocoded.has(key)) return Promise.resolve(geocoded.get(key) ?? null)
  return new Promise((resolve) => {
    const search = new mapkit.Search(near ? { coordinate: new mapkit.Coordinate(near.latitude, near.longitude) } : {})
    search.search(query, (error, data) => {
      const place = !error && data.places[0]
      const result = place ? { latitude: place.coordinate.latitude, longitude: place.coordinate.longitude } : null
      geocoded.set(key, result)
      resolve(result)
    })
  })
}
