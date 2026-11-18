/**
 * Public settings. None of this is secret: a Firebase web config is public by
 * design, and Firestore security rules are what protect the data. Any value can
 * be overridden with a VITE_* variable in a .env.local file.
 */
const env = import.meta.env

export const config = {
  firebase: {
    // TODO: replace apiKey and appId with the Web app's values from
    // Firebase console › Project settings › Your apps, once the Web app is added.
    // This apiKey is the iPhone app's; it only works if that key isn't limited to iOS apps.
    apiKey: env.VITE_FIREBASE_API_KEY || 'AIzaSyAuhOm_2fa44gHiM7nvZm8NGBhqzxN1gOQ',
    authDomain: env.VITE_FIREBASE_AUTH_DOMAIN || 'agdayo-app.firebaseapp.com',
    projectId: env.VITE_FIREBASE_PROJECT_ID || 'agdayo-app',
    storageBucket: env.VITE_FIREBASE_STORAGE_BUCKET || 'agdayo-app.firebasestorage.app',
    messagingSenderId: env.VITE_FIREBASE_MESSAGING_SENDER_ID || '1015175012900',
    appId: env.VITE_FIREBASE_APP_ID || undefined,
  },
  /** The Agdayo Worker (API + MCP connector). The old https://agdayo.albertcorpmail.workers.dev still works too. */
  workerUrl: env.VITE_WORKER_URL || 'https://api.agdayo.app',
  /** Where "Get the app" links go. TODO: the app's App Store link. */
  appStoreUrl: env.VITE_APP_STORE_URL || '',
}
