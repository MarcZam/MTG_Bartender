import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabaseClient'
import Auth from '../components/Auth'

type EventRow = {
  id: string
  title: string
  description?: string
  start_datetime?: string
}

export default function Home() {
  const [events, setEvents] = useState<EventRow[]>([])

  useEffect(() => {
    fetchEvents()
  }, [])

  async function fetchEvents() {
    const { data, error } = await supabase.from('events').select('id, title, description, start_datetime').order('start_datetime', { ascending: true }).limit(50)
    if (error) {
      console.error(error)
      return
    }
    setEvents(data as EventRow[])
  }

  return (
    <div className="container">
      <h1>MTG Bartender — Events</h1>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 320px', gap: 20 }}>
        <div>
          {events.length === 0 && <div className="card">No events yet.</div>}
          {events.map((ev) => (
            <div key={ev.id} className="card" style={{ marginBottom: 12 }}>
              <h3>{ev.title}</h3>
              <p>{ev.description}</p>
              <small>{ev.start_datetime}</small>
            </div>
          ))}
        </div>
        <aside>
          <div className="card">
            <h3>Your account</h3>
            <Auth />
          </div>
          <div className="card" style={{ marginTop: 12 }}>
            <h4>Create demo event</h4>
            <a className="btn" href="/create-event">Create</a>
          </div>
        </aside>
      </div>
    </div>
  )
}
