import { useCallback, useEffect, useState } from 'react'
import { useParams } from 'react-router-dom'
import { Loader2, LogOut } from 'lucide-react'
import { browserSupabase } from '../lib/browser-supabase.js'
import { fetchRoleProfile } from '../lib/roleProfile.js'
import type { RoleProfileRow } from '../types/roleProfile.js'
import { Shell } from '../components/Shell.js'
import { Button } from '../components/ui/button.js'
import { Card, CardBody } from '../components/ui/card.js'
import { TabBand, Tab } from '../components/ui/tabband.js'
import { StubBanner } from '../components/role-profile/StubBanner.js'
import { PageHeader } from '../components/role-profile/PageHeader.js'
import { SubNav } from '../components/role-profile/SubNav.js'
import {
  IdentityGovernanceSection, TasksSection, CompetenciesSection, TraitTargetsSection,
  CognitiveDemandSection, ContextFactorsSection, ValuesSection, SuccessCriteriaSection,
  EvolutionVectorSection, TeamGapSection,
} from '../components/role-profile/Sections.js'
import { ValidationCard } from '../components/role-profile/ValidationCard.js'

export function RoleProfilePage() {
  const { id, version } = useParams<{ id: string; version?: string }>()
  const supabase = browserSupabase()
  const [signedIn, setSignedIn] = useState<string | null>(null)
  const [row, setRow] = useState<RoleProfileRow | null | undefined>(undefined)
  const [err, setErr] = useState<string | null>(null)
  const [tab, setTab] = useState<'profile' | 'team_definition' | 'versions' | 'defensibility' | 'manage'>('profile')

  useEffect(() => {
    void supabase.auth.getSession().then(({ data }) => setSignedIn(data.session?.user?.email ?? null))
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setSignedIn(s?.user?.email ?? null))
    return () => sub.subscription.unsubscribe()
  }, [supabase])

  const reload = useCallback(() => {
    if (!id) return
    setRow(undefined); setErr(null)
    const v = version ? Number(version) : undefined
    fetchRoleProfile(supabase, id, v)
      .then(r => setRow(r))
      .catch(e => { setErr(e instanceof Error ? e.message : 'Failed to load'); setRow(null) })
  }, [supabase, id, version])

  useEffect(() => { reload() }, [reload])

  if (!signedIn) {
    return (
      <Shell breadcrumb={<span>Role profile</span>}>
        <Card><CardBody>
          <p>You must sign in to view a role profile.</p>
          <Button onClick={async () => {
            await supabase.auth.signInWithPassword({ email: 'linnea.strand@fjordtech.test', password: 'demo' })
          }}>Sign in as Linnea (demo)</Button>
        </CardBody></Card>
      </Shell>
    )
  }

  return (
    <Shell breadcrumb={<span>Role profile · <strong>{row?.title ?? '…'}</strong></span>} signedInLabel={signedIn}>
      <div className="flex flex-col gap-4">
        {err && <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-900">{err}</div>}
        {row === undefined && (
          <div className="text-faint text-sm flex items-center gap-2"><Loader2 size={14} className="animate-spin" /> Loading role profile…</div>
        )}
        {row === null && !err && (
          <Card><CardBody><p className="text-faint">Not found, or you don't have access to this role.</p></CardBody></Card>
        )}

        {row && (
          <>
            <PageHeader row={row} onChanged={reload} />

            {/* Forest tab band — only the Profile tab is built in this work */}
            <TabBand>
              <Tab active={tab === 'profile'} onClick={() => setTab('profile')}>Profile</Tab>
              <Tab active={tab === 'team_definition'} onClick={() => setTab('team_definition')}>Team definition</Tab>
              <Tab active={tab === 'versions'} onClick={() => setTab('versions')}>Version history</Tab>
              <Tab active={tab === 'defensibility'} onClick={() => setTab('defensibility')}>Defensibility</Tab>
              <Tab active={tab === 'manage'} onClick={() => setTab('manage')}>Manage</Tab>
            </TabBand>

            {tab !== 'profile' && (
              <Card><CardBody>
                <p className="text-faint text-sm">
                  <em>The {tab.replace('_', ' ')} tab is a placeholder shell — separate work.</em>
                </p>
                <div className="text-xs font-mono text-faint mt-2">TODO: wire to underlying queries.</div>
              </CardBody></Card>
            )}

            {tab === 'profile' && (
              <>
                <StubBanner row={row} />
                <div className="flex gap-6">
                  <SubNav />
                  <div className="flex-1 flex flex-col gap-4 min-w-0">
                    <IdentityGovernanceSection row={row} />
                    <TasksSection row={row} />
                    <CompetenciesSection row={row} />
                    <TraitTargetsSection row={row} />
                    <CognitiveDemandSection row={row} />
                    <ContextFactorsSection row={row} />
                    <ValuesSection row={row} />
                    <SuccessCriteriaSection row={row} />
                    <EvolutionVectorSection row={row} />
                    <TeamGapSection row={row} />
                    <ValidationCard row={row} />
                  </div>
                </div>
              </>
            )}
          </>
        )}

        <div className="flex justify-end pt-4 border-t border-line">
          <Button variant="ghost" onClick={() => supabase.auth.signOut()}><LogOut size={14} /> Sign out</Button>
        </div>
      </div>
    </Shell>
  )
}
