import { useState } from 'react'
import { supabase } from '@/lib/supabaseClient'
import { useAuth } from '@/lib/auth'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'

export default function Auth() {
  const { user } = useAuth()
  const [email, setEmail] = useState('')
  const [message, setMessage] = useState('')
  const [loading, setLoading] = useState(false)

  const signIn = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    setMessage('')
    const { error } = await supabase.auth.signInWithOtp({ email })
    setLoading(false)
    if (error) setMessage(error.message)
    else setMessage('Check your email for a sign-in link.')
  }

  const signOut = async () => {
    await supabase.auth.signOut()
  }

  if (user) {
    return (
      <div className="space-y-3">
        <p className="text-sm text-muted-foreground">
          Signed in as <span className="font-medium text-foreground">{user.email}</span>
        </p>
        <Button variant="outline" size="sm" onClick={signOut} className="w-full">
          Sign out
        </Button>
      </div>
    )
  }

  return (
    <form onSubmit={signIn} className="space-y-3">
      <div className="space-y-1.5">
        <Label htmlFor="email">Email</Label>
        <Input
          id="email"
          type="email"
          placeholder="you@example.com"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          required
        />
      </div>
      <Button type="submit" className="w-full" disabled={loading}>
        {loading ? 'Sending…' : 'Send magic link'}
      </Button>
      {message && (
        <p className="text-xs text-muted-foreground text-center">{message}</p>
      )}
    </form>
  )
}
