import { useState } from 'react'
import { supabase } from '../lib/supabaseClient'
import { useAuth } from '../lib/auth'

export default function Auth() {
  const { user } = useAuth()
  const [email, setEmail] = useState('')
  const [message, setMessage] = useState('')

  const signIn = async (e: React.FormEvent) => {
    e.preventDefault()
    setMessage('')
    const { error } = await supabase.auth.signInWithOtp({ email })
    if (error) setMessage(error.message)
    else setMessage('Check your email for a sign-in link.')
  }

  const signOut = async () => {
    await supabase.auth.signOut()
    setMessage('Signed out')
  }

  if (user) {
    return (
      <div>
        <p>Signed in as <strong>{user.email}</strong></p>
        <button className="btn" onClick={signOut}>Sign out</button>
        {message && <p style={{ marginTop: 8 }}>{message}</p>}
      </div>
    )
  }

  return (
    <div className="card">
      <h3>Sign in</h3>
      <form onSubmit={signIn}>
        <input
          placeholder="you@example.com"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          style={{ padding: 8, width: '100%', marginBottom: 8 }}
        />
        <button className="btn" type="submit">Send magic link</button>
      </form>
      {message && <p style={{ marginTop: 8 }}>{message}</p>}
    </div>
  )
}
