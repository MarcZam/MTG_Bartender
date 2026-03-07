import { useState } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/router'
import { ArrowLeft, Swords } from 'lucide-react'
import { supabase } from '@/lib/supabaseClient'
import { useAuth } from '@/lib/auth'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'

type FormState = {
  title: string
  description: string
  start_datetime: string
  entry_fee: string
  game_system: string
}

const GAME_SYSTEMS = [
  { value: 'mtg', label: 'Magic: The Gathering' },
  { value: 'pokemon', label: 'Pokémon' },
  { value: 'lorcana', label: 'Lorcana' },
  { value: 'flesh_and_blood', label: 'Flesh & Blood' },
  { value: 'yugioh', label: 'Yu-Gi-Oh!' },
  { value: 'other', label: 'Other' },
]

export default function CreateEvent() {
  const { user } = useAuth()
  const router = useRouter()

  const [form, setForm] = useState<FormState>({
    title: '',
    description: '',
    start_datetime: '',
    entry_fee: '0',
    game_system: 'mtg',
  })
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  const set = (field: keyof FormState) => (
    e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>
  ) => setForm((prev) => ({ ...prev, [field]: e.target.value }))

  const submit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!user) {
      setError('You must be signed in to create an event.')
      return
    }
    setError('')
    setLoading(true)

    const { error: supaErr } = await supabase.from('events').insert([
      {
        title: form.title,
        description: form.description || null,
        start_datetime: form.start_datetime || null,
        entry_fee: parseFloat(form.entry_fee) || 0,
        game_system: form.game_system,
        created_by: user.id,
        status: 'published',
        is_public: true,
      },
    ])

    setLoading(false)
    if (supaErr) {
      setError(supaErr.message)
    } else {
      router.push('/')
    }
  }

  return (
    <div className="min-h-screen bg-background">
      {/* Header */}
      <header className="sticky top-0 z-10 border-b bg-background/95 backdrop-blur">
        <div className="max-w-5xl mx-auto px-4 h-14 flex items-center gap-3">
          <Swords className="h-5 w-5" />
          <span className="font-bold text-lg tracking-tight">MTG Bartender</span>
        </div>
      </header>

      <main className="max-w-xl mx-auto px-4 py-8">
        <Button variant="ghost" size="sm" asChild className="mb-4 -ml-2">
          <Link href="/">
            <ArrowLeft className="h-4 w-4 mr-1" />
            Back to events
          </Link>
        </Button>

        <Card>
          <CardHeader>
            <CardTitle>Create an event</CardTitle>
            <CardDescription>
              Fill in the details below. You can add tournaments to the event afterwards.
            </CardDescription>
          </CardHeader>

          <CardContent>
            {!user && (
              <p className="text-sm text-destructive mb-4">
                You must be signed in to create an event.
              </p>
            )}

            <form onSubmit={submit} className="space-y-4">
              {/* Title */}
              <div className="space-y-1.5">
                <Label htmlFor="title">Event title *</Label>
                <Input
                  id="title"
                  placeholder="Friday Night Magic — Store Open"
                  value={form.title}
                  onChange={set('title')}
                  required
                />
              </div>

              {/* Description */}
              <div className="space-y-1.5">
                <Label htmlFor="description">Description</Label>
                <Textarea
                  id="description"
                  placeholder="What should players know before signing up?"
                  value={form.description}
                  onChange={set('description')}
                  rows={3}
                />
              </div>

              {/* Game system */}
              <div className="space-y-1.5">
                <Label htmlFor="game_system">Game system</Label>
                <select
                  id="game_system"
                  value={form.game_system}
                  onChange={set('game_system')}
                  className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
                >
                  {GAME_SYSTEMS.map((g) => (
                    <option key={g.value} value={g.value}>
                      {g.label}
                    </option>
                  ))}
                </select>
              </div>

              {/* Date / time */}
              <div className="space-y-1.5">
                <Label htmlFor="start_datetime">Date & time</Label>
                <Input
                  id="start_datetime"
                  type="datetime-local"
                  value={form.start_datetime}
                  onChange={set('start_datetime')}
                />
              </div>

              {/* Entry fee */}
              <div className="space-y-1.5">
                <Label htmlFor="entry_fee">Entry fee (€)</Label>
                <Input
                  id="entry_fee"
                  type="number"
                  min="0"
                  step="0.5"
                  value={form.entry_fee}
                  onChange={set('entry_fee')}
                />
              </div>

              {error && <p className="text-sm text-destructive">{error}</p>}

              <div className="flex gap-2 pt-2">
                <Button type="submit" disabled={loading || !user} className="flex-1">
                  {loading ? 'Creating…' : 'Create event'}
                </Button>
                <Button type="button" variant="outline" asChild>
                  <Link href="/">Cancel</Link>
                </Button>
              </div>
            </form>
          </CardContent>
        </Card>
      </main>
    </div>
  )
}
