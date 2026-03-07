import { useEffect, useState } from 'react'
import Link from 'next/link'
import { CalendarDays, MapPin, Swords } from 'lucide-react'
import { supabase } from '@/lib/supabaseClient'
import { useAuth } from '@/lib/auth'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import Auth from '@/components/Auth'

type EventRow = {
  id: string
  title: string
  description?: string
  start_datetime?: string
  game_system?: string
  entry_fee?: number
}

const GAME_SYSTEM_LABELS: Record<string, string> = {
  mtg: 'MTG',
  pokemon: 'Pokémon',
  lorcana: 'Lorcana',
  flesh_and_blood: 'Flesh & Blood',
  yugioh: 'Yu-Gi-Oh!',
  other: 'Other',
}

export default function Home() {
  const { user } = useAuth()
  const [events, setEvents] = useState<EventRow[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    fetchEvents()
  }, [])

  async function fetchEvents() {
    const { data, error } = await supabase
      .from('events')
      .select('id, title, description, start_datetime, game_system, entry_fee')
      .order('start_datetime', { ascending: true })
      .limit(50)
    setLoading(false)
    if (!error && data) setEvents(data as EventRow[])
  }

  return (
    <div className="min-h-screen bg-background">
      {/* Header */}
      <header className="sticky top-0 z-10 border-b bg-background/95 backdrop-blur">
        <div className="max-w-5xl mx-auto px-4 h-14 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Swords className="h-5 w-5" />
            <span className="font-bold text-lg tracking-tight">MTG Bartender</span>
          </div>
          <nav className="flex items-center gap-2">
            {user && (
              <Button asChild size="sm">
                <Link href="/create-event">+ New Event</Link>
              </Button>
            )}
          </nav>
        </div>
      </header>

      {/* Main layout */}
      <main className="max-w-5xl mx-auto px-4 py-8 grid grid-cols-1 md:grid-cols-[1fr_280px] gap-6">

        {/* Event list */}
        <section>
          <h2 className="text-xl font-semibold mb-4">Upcoming Events</h2>

          {loading && (
            <div className="space-y-3">
              {[1, 2, 3].map((i) => (
                <div key={i} className="h-24 rounded-lg border bg-muted animate-pulse" />
              ))}
            </div>
          )}

          {!loading && events.length === 0 && (
            <Card>
              <CardContent className="py-10 text-center text-muted-foreground">
                No upcoming events yet. Be the first to create one!
              </CardContent>
            </Card>
          )}

          <div className="space-y-3">
            {events.map((ev) => (
              <Card key={ev.id} className="hover:shadow-md transition-shadow">
                <CardHeader className="pb-2">
                  <div className="flex items-start justify-between gap-2">
                    <CardTitle className="text-base">{ev.title}</CardTitle>
                    {ev.game_system && (
                      <Badge variant="secondary" className="shrink-0">
                        {GAME_SYSTEM_LABELS[ev.game_system] ?? ev.game_system}
                      </Badge>
                    )}
                  </div>
                  {ev.description && (
                    <CardDescription className="line-clamp-2">{ev.description}</CardDescription>
                  )}
                </CardHeader>
                <CardContent className="pt-0 flex items-center gap-4 text-xs text-muted-foreground">
                  {ev.start_datetime && (
                    <span className="flex items-center gap-1">
                      <CalendarDays className="h-3 w-3" />
                      {new Date(ev.start_datetime).toLocaleString(undefined, {
                        dateStyle: 'medium',
                        timeStyle: 'short',
                      })}
                    </span>
                  )}
                  {ev.entry_fee !== undefined && ev.entry_fee > 0 && (
                    <span className="ml-auto font-medium text-foreground">
                      €{ev.entry_fee.toFixed(2)}
                    </span>
                  )}
                  {ev.entry_fee === 0 && (
                    <span className="ml-auto text-green-600 font-medium">Free</span>
                  )}
                </CardContent>
              </Card>
            ))}
          </div>
        </section>

        {/* Sidebar */}
        <aside className="space-y-4">
          <Card>
            <CardHeader className="pb-3">
              <CardTitle className="text-base">
                {user ? 'Your account' : 'Sign in'}
              </CardTitle>
            </CardHeader>
            <CardContent>
              <Auth />
            </CardContent>
          </Card>

          {user && (
            <Card>
              <CardContent className="pt-6">
                <Button asChild className="w-full">
                  <Link href="/create-event">Create an event</Link>
                </Button>
              </CardContent>
            </Card>
          )}
        </aside>
      </main>
    </div>
  )
}
