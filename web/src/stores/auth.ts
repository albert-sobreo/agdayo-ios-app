import { defineStore } from 'pinia'
import { ref } from 'vue'
import {
  createUserWithEmailAndPassword, GoogleAuthProvider, OAuthProvider, onAuthStateChanged,
  sendPasswordResetEmail, signInWithEmailAndPassword, signInWithPopup, signOut as firebaseSignOut,
  updateProfile, type User,
} from 'firebase/auth'
import { FirebaseError } from 'firebase/app'
import { auth } from '@/firebase'
import { ensureUserDocument } from '@/lib/writes'

/** Same three ways in as the iPhone app (AuthService.swift), so the same account works on both. */
export const useAuthStore = defineStore('auth', () => {
  const user = ref<User | null>(null)
  /** False until Firebase has said whether someone is signed in. */
  const ready = ref(false)
  let readyResolve: () => void = () => {}
  const readyPromise = new Promise<void>((resolve) => (readyResolve = resolve))

  onAuthStateChanged(auth, (next) => {
    user.value = next
    ready.value = true
    readyResolve()
    if (next) ensureUserDocument(next).catch((error) => console.warn('Could not update the profile', error))
  })

  async function signInWithGoogle() {
    await signInWithPopup(auth, new GoogleAuthProvider())
  }

  async function signInWithApple() {
    const provider = new OAuthProvider('apple.com')
    provider.addScope('email')
    provider.addScope('name')
    await signInWithPopup(auth, provider)
  }

  async function signInWithEmail(email: string, password: string) {
    await signInWithEmailAndPassword(auth, email.trim(), password)
  }

  async function signUpWithEmail(name: string, email: string, password: string) {
    const credential = await createUserWithEmailAndPassword(auth, email.trim(), password)
    if (name.trim()) {
      await updateProfile(credential.user, { displayName: name.trim() })
      await ensureUserDocument(credential.user)
    }
  }

  async function resetPassword(email: string) {
    await sendPasswordResetEmail(auth, email.trim())
  }

  async function signOut() {
    await firebaseSignOut(auth)
  }

  return {
    user, ready, whenReady: () => readyPromise,
    signInWithGoogle, signInWithApple, signInWithEmail, signUpWithEmail, resetPassword, signOut,
  }
})

/** A sentence a person can act on, for any sign-in error. Null when they just closed the popup. */
export function authErrorMessage(error: unknown): string | null {
  if (!(error instanceof FirebaseError)) return 'Something went wrong. Please try again.'
  switch (error.code) {
    case 'auth/popup-closed-by-user':
    case 'auth/cancelled-popup-request':
      return null
    case 'auth/popup-blocked':
      return 'Your browser blocked the sign-in window. Allow pop-ups for this site and try again.'
    case 'auth/invalid-credential':
    case 'auth/wrong-password':
    case 'auth/user-not-found':
      return 'That email and password don’t match an Agdayo account.'
    case 'auth/email-already-in-use':
      return 'There’s already an account with this email. Sign in instead.'
    case 'auth/weak-password':
      return 'Use a password with at least 6 characters.'
    case 'auth/invalid-email':
      return 'That email address doesn’t look right.'
    case 'auth/account-exists-with-different-credential':
      return 'This email already signs in another way. Use the button you used in the iPhone app.'
    case 'auth/unauthorized-domain':
    case 'auth/operation-not-allowed':
      return 'This sign-in method isn’t set up for the web yet.'
    case 'auth/network-request-failed':
      return 'You seem to be offline. Check your connection and try again.'
    default:
      return error.message
  }
}
