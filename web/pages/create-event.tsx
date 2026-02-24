import { useState } from 'react'
import { supabase } from '../lib/supabaseClient'

export default function CreateEvent() {
  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')
  const [message, setMessage] = useState('')

  const submit = async (e: React.FormEvent) => {
    e.preventDefault()
    setMessage('')
    const { data, error } = await supabase.from('events').insert([{ title, description }])
    if (error) setMessage(error.message)
    else setMessage('Event created')
  }

  return (
    <div className="container">
      <h1>Create Event</h1>
      <div className="card">
        <form onSubmit={submit}>
          <div style={{ marginBottom: 8 }}>
            <label>Title</label>
            <input value={title} onChange={(e) => setTitle(e.target.value)} style={{ width: '100%', padding: 8 }} />
          </div>
          <div style={{ marginBottom: 8 }}>
            <label>Description</label>
            <textarea value={description} onChange={(e) => setDescription(e.target.value)} style={{ width: '100%', padding: 8 }} />
          </div>
          <button className="btn" type="submit">Create</button>
        </form>
        {message && <p style={{ marginTop: 8 }}>{message}</p>}
      </div>
    </div>
  )
}
