import { useCallback, useEffect, useState } from 'react'
import { LogIn, LogOut, User } from 'lucide-react'
import { browserSupabase } from '../lib/browser-supabase.js'
import { Button } from '../components/ui/button.js'
import { Select } from '../components/ui/select.js'
import { Card, CardBody, CardTitle, CardEyebrow } from '../components/ui/card.js'
import { Table, THead, TBody, TR, TH, TD } from '../components/ui/table.js'

const DEMO_USERS = [
  { email: 'astrid.berg@nordic-recruit.test',   label: 'Astrid Berg — Nordic Recruit org_admin' },
  { email: 'magnus.holm@nordic-recruit.test',   label: 'Magnus Holm — Nordic Recruit recruiter' },
  { email: 'linnea.strand@fjordtech.test',      label: 'Linnea Strand — FjordTech people_ops_admin' },
  { email: 'erik.lund@fjordtech.test',          label: 'Erik Lund — FjordTech hiring_manager' },
  { email: 'sara.vik@fjordtech.test',           label: 'Sara Vik — FjordTech manager' },
  { email: 'jonas.dahl@fjordtech.test',         label: 'Jonas Dahl — FjordTech employee' },
  { email: 'petra.nilsson@candidate.test',      label: 'Petra Nilsson — candidate (data subject)' },
  { email: 'henrik.ek@candidate.test',          label: 'Henrik Ek — candidate (no consent)' },
] as const

type PersonRow = {
  id: string
  primary_email: string
  full_name: string
  given_name: string | null
  family_name: string | null
}

const DEMO_PASSWORD = 'demo'

export function PeoplePage() {
  const supabase = browserSupabase()
  const [signedInEmail, setSignedInEmail] = useState<string | null>(null)
  const [selectedEmail, setSelectedEmail] = useState<string>(DEMO_USERS[0].email)
  const [people, setPeople] = useState<PersonRow[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const refresh = useCallback(async () => {
    setLoading(true)
    setError(null)
    const { data, error: err } = await supabase
      .from('people')
      .select('id, primary_email, full_name, given_name, family_name')
      .order('full_name')
    if (err) setError(err.message)
    setPeople((data ?? []) as PersonRow[])
    setLoading(false)
  }, [supabase])

  useEffect(() => {
    void supabase.auth.getSession().then(({ data }) => {
      const email = data.session?.user?.email ?? null
      setSignedInEmail(email)
      if (email) void refresh()
    })
  }, [supabase, refresh])

  async function signIn() {
    setError(null)
    const { error: err } = await supabase.auth.signInWithPassword({
      email: selectedEmail,
      password: DEMO_PASSWORD,
    })
    if (err) {
      setError(`Sign-in failed: ${err.message}. Did you run \`npm run setup:demo-passwords\`?`)
      return
    }
    setSignedInEmail(selectedEmail)
    await refresh()
  }

  async function signOut() {
    await supabase.auth.signOut()
    setSignedInEmail(null)
    setPeople([])
  }

  return (
    <main className="min-h-screen bg-canvas p-8">
      <div className="mx-auto max-w-5xl space-y-6">
        <header className="space-y-2">
          <p className="eyebrow">HeiTobias · Phase 0 smoke</p>
          <h1 className="font-display text-[40px] font-semibold tracking-tight leading-none">
            People <span className="text-muted italic font-normal">— what your role lets you see</span>
          </h1>
          <p className="text-muted text-sm max-w-2xl">
            Pick a seeded user, sign in, and the table below re-queries through their JWT.
            Postgres RLS decides what rows you get. Not the real product UI.
          </p>
        </header>

        <Card>
          <CardBody className="space-y-4">
            <CardEyebrow>Switch user</CardEyebrow>
            {signedInEmail ? (
              <div className="flex items-center gap-3 flex-wrap">
                <div className="flex items-center gap-2 text-sm">
                  <User className="h-4 w-4 text-person" aria-hidden /> Signed in as <strong>{signedInEmail}</strong>
                </div>
                <div className="flex-1" />
                <Button variant="ghost" onClick={signOut}>
                  <LogOut className="h-4 w-4" aria-hidden /> Sign out
                </Button>
              </div>
            ) : (
              <div className="flex items-center gap-3 flex-wrap">
                <Select
                  value={selectedEmail}
                  onChange={(e) => setSelectedEmail(e.target.value)}
                  className="max-w-md"
                >
                  {DEMO_USERS.map((u) => (
                    <option key={u.email} value={u.email}>{u.label}</option>
                  ))}
                </Select>
                <Button onClick={signIn}>
                  <LogIn className="h-4 w-4" aria-hidden /> Sign in
                </Button>
              </div>
            )}
            {error && (
              <p className="text-xs text-rust border border-rust/30 bg-reject-bg/30 rounded p-3">
                {error}
              </p>
            )}
          </CardBody>
        </Card>

        <Card>
          <CardBody>
            <div className="flex items-end justify-between gap-4 mb-4">
              <div>
                <CardEyebrow>Person entity</CardEyebrow>
                <CardTitle className="text-2xl">People you can see</CardTitle>
              </div>
              <div className="eyebrow">
                {loading ? 'loading…' : `${people.length} row${people.length === 1 ? '' : 's'}`}
              </div>
            </div>

            {!signedInEmail ? (
              <p className="text-muted text-sm">Sign in above to query the people table.</p>
            ) : people.length === 0 ? (
              <p className="text-muted text-sm">
                No rows — RLS returned zero. (E.g. a candidate without an org membership has
                no scope to see anyone but themselves.)
              </p>
            ) : (
              <Table>
                <THead>
                  <TR>
                    <TH>Name</TH>
                    <TH>Email</TH>
                    <TH>Person ID</TH>
                  </TR>
                </THead>
                <TBody>
                  {people.map((p) => (
                    <TR key={p.id}>
                      <TD className="font-semibold">{p.full_name}</TD>
                      <TD className="text-xs text-muted">{p.primary_email}</TD>
                      <TD className="text-xs text-muted">{p.id.slice(0, 8)}…</TD>
                    </TR>
                  ))}
                </TBody>
              </Table>
            )}
          </CardBody>
        </Card>

        <footer className="text-xs text-muted">
          DEV ONLY · running against {import.meta.env.VITE_SUPABASE_URL?.replace('https://', '')} · production must be EU-region
        </footer>
      </div>
    </main>
  )
}
