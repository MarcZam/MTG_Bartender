import React, { createContext, useContext, useEffect, useState } from 'react'
import type { Session, User } from '@supabase/supabase-js'
import { supabase } from '@/lib/supabaseClient'

type AuthContextType = {
  session: Session | null
  user: User | null
}

const AuthContext = createContext<AuthContextType>({ session: null, user: null })

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [user, setUser] = useState<User | null>(null)

  useEffect(() => {
    let mounted = true

    supabase.auth.getSession().then(({ data: { session: s } }) => {
      if (!mounted) return
      setSession(s ?? null)
      setUser(s?.user ?? null)
    })

    const { data } = supabase.auth.onAuthStateChange((_event, newSession) => {
      setSession(newSession ?? null)
      setUser(newSession?.user ?? null)
    })

    return () => {
      mounted = false
      data.subscription.unsubscribe()
    }
  }, [])

  return <AuthContext.Provider value={{ session, user }}>{children}</AuthContext.Provider>
}

export function useAuth() {
  return useContext(AuthContext)
}
