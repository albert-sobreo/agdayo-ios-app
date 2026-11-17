import { initializeApp } from 'firebase/app'
import { config } from '@/config'
import { browserLocalPersistence, getAuth, setPersistence } from 'firebase/auth'
import { initializeFirestore, persistentLocalCache, persistentMultipleTabManager } from 'firebase/firestore'

/** Same Firebase project as the iPhone app, so accounts and trips are shared. */
export const firebaseApp = initializeApp(config.firebase)

export const auth = getAuth(firebaseApp)
void setPersistence(auth, browserLocalPersistence)

/** Cached in the browser, so trips open instantly and survive a flaky connection. */
export const db = initializeFirestore(firebaseApp, {
  localCache: persistentLocalCache({ tabManager: persistentMultipleTabManager() }),
})
