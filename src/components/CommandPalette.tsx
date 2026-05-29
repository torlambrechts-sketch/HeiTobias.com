import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Briefcase, Search, User, Users, X, FileText } from 'lucide-react'
import { browserSupabase } from '../lib/browser-supabase.js'

// Cmd-K / Ctrl-K global search.
//
// Searches four entity types in parallel, RLS-scoped:
//   * people            (full_name ILIKE %q% OR primary_email ILIKE %q%)
//   * roles_catalog     (title ILIKE %q% OR family ILIKE %q%)
//   * requisitions      (by role title via a join)
//   * organizations     (name ILIKE %q%)
//
// Each result is a navigable link. Keyboard:
//   ↑ / ↓ — move selection
//   ↵     — open selected
//   Esc   — close
//
// Why this isn't backed by a single full-text-search RPC: the four
// queries each respect their respective RLS policies natively. A
// single search RPC would either need to UNION across all of them
// with security-definer (risking a privilege creep) or build a search
// index that has to be invalidated on every relevant insert. The
// four-parallel-queries approach is simpler and stays correct under
// RLS without extra infrastructure.

type Hit =
  | { kind: 'person';       id: string; label: string; sub: string; href: string }
  | { kind: 'role';         id: string; label: string; sub: string; href: string }
  | { kind: 'requisition';  id: string; label: string; sub: string; href: string }
  | { kind: 'org';          id: string; label: string; sub: string; href: string }

const DEBOUNCE_MS = 180

export function CommandPalette() {
  const supabase = browserSupabase()
  const navigate = useNavigate()
  const [open, setOpen] = useState(false)
  const [query, setQuery] = useState('')
  const [hits, setHits] = useState<Hit[]>([])
  const [loading, setLoading] = useState(false)
  const [selected, setSelected] = useState(0)
  const inputRef = useRef<HTMLInputElement>(null)

  // Global Cmd-K / Ctrl-K listener.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const isCmdK = (e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k'
      if (isCmdK) {
        e.preventDefault()
        setOpen(prev => !prev)
      }
    }
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [])

  useEffect(() => {
    if (open) {
      // Focus on next tick — input has just mounted.
      const id = window.setTimeout(() => inputRef.current?.focus(), 10)
      return () => window.clearTimeout(id)
    }
    setQuery('')
    setHits([])
    setSelected(0)
    return undefined
  }, [open])

  // Debounced search across the four entity types.
  useEffect(() => {
    if (!open) return
    const q = query.trim()
    if (q.length < 2) { setHits([]); return }
    let cancelled = false
    setLoading(true)
    const id = window.setTimeout(async () => {
      const pattern = `%${q}%`
      const [pp, rr, qq, oo] = await Promise.all([
        supabase.from('people')
          .select('id, full_name, primary_email')
          .or(`full_name.ilike.${pattern},primary_email.ilike.${pattern}`)
          .limit(8),
        supabase.from('roles_catalog')
          .select('id, title, family, version, is_template')
          .eq('is_template', false)
          .or(`title.ilike.${pattern},family.ilike.${pattern}`)
          .limit(8),
        supabase.from('requisitions')
          .select('id, status, role:roles_catalog(title, family)')
          .limit(20),
        supabase.from('organizations')
          .select('id, name, type')
          .ilike('name', pattern)
          .limit(5),
      ])
      if (cancelled) return
      const results: Hit[] = []
      for (const p of (pp.data ?? []) as Array<{ id: string; full_name: string; primary_email: string }>) {
        results.push({
          kind: 'person', id: p.id,
          label: p.full_name, sub: p.primary_email,
          href: `/employees/${p.id}`,
        })
      }
      for (const r of (rr.data ?? []) as Array<{ id: string; title: string; family: string | null; version: number }>) {
        results.push({
          kind: 'role', id: r.id,
          label: r.title, sub: `v${r.version}${r.family ? ` · ${r.family}` : ''}`,
          href: `/roles/${r.id}`,
        })
      }
      for (const rq of (qq.data ?? []) as Array<{ id: string; status: string; role: { title: string; family: string | null } | null }>) {
        const t = rq.role?.title ?? '(no role)'
        if (!t.toLowerCase().includes(q.toLowerCase())) continue
        results.push({
          kind: 'requisition', id: rq.id,
          label: t, sub: `requisition · ${rq.status}`,
          href: `/requisitions/${rq.id}`,
        })
      }
      for (const o of (oo.data ?? []) as Array<{ id: string; name: string; type: string }>) {
        results.push({
          kind: 'org', id: o.id,
          label: o.name, sub: o.type,
          href: '/admin',
        })
      }
      setHits(results)
      setSelected(0)
      setLoading(false)
    }, DEBOUNCE_MS)
    return () => { cancelled = true; window.clearTimeout(id) }
  }, [open, query, supabase])

  const go = useCallback((h: Hit) => {
    navigate(h.href)
    setOpen(false)
  }, [navigate])

  const onKeyDown = useCallback((e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Escape') { setOpen(false); return }
    if (e.key === 'ArrowDown') { e.preventDefault(); setSelected(s => Math.min(s + 1, Math.max(0, hits.length - 1))); return }
    if (e.key === 'ArrowUp')   { e.preventDefault(); setSelected(s => Math.max(s - 1, 0)); return }
    if (e.key === 'Enter')     {
      if (hits[selected]) { e.preventDefault(); go(hits[selected]) }
    }
  }, [hits, selected, go])

  const groups = useMemo(() => {
    const order: Hit['kind'][] = ['person', 'role', 'requisition', 'org']
    const labels: Record<Hit['kind'], string> = {
      person: 'People', role: 'Roles', requisition: 'Requisitions', org: 'Organisations',
    }
    return order
      .map(k => ({ kind: k, label: labels[k], items: hits.filter(h => h.kind === k) }))
      .filter(g => g.items.length > 0)
  }, [hits])

  if (!open) return null

  return (
    <div
      role="dialog"
      aria-label="Command palette"
      className="fixed inset-0 z-50 bg-ink/40 backdrop-blur-sm flex items-start justify-center pt-24 px-4"
      onClick={() => setOpen(false)}
    >
      <div
        className="w-full max-w-xl bg-surface border border-line rounded-lg shadow-hard overflow-hidden"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center gap-2 border-b border-line px-3 py-2">
          <Search size={16} className="text-muted" />
          <input
            ref={inputRef}
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={onKeyDown}
            placeholder="Search people, roles, requisitions, organisations…"
            className="flex-1 bg-transparent text-sm outline-none placeholder:text-faint"
            aria-label="Search"
          />
          <kbd className="text-[10.5px] font-mono text-faint border border-line rounded px-1 py-0.5">esc</kbd>
          <button type="button" onClick={() => setOpen(false)} className="text-muted hover:text-ink p-1" aria-label="Close">
            <X size={14} />
          </button>
        </div>

        <div className="max-h-[400px] overflow-y-auto py-1">
          {query.trim().length < 2 && (
            <div className="px-4 py-8 text-center text-xs text-faint">
              Type at least two characters. Search is scoped to what you can see (RLS).
            </div>
          )}
          {query.trim().length >= 2 && loading && hits.length === 0 && (
            <div className="px-4 py-6 text-center text-xs text-faint">Searching…</div>
          )}
          {query.trim().length >= 2 && !loading && hits.length === 0 && (
            <div className="px-4 py-8 text-center text-xs text-faint">No matches.</div>
          )}
          {groups.map(g => (
            <div key={g.kind} className="py-1">
              <div className="px-3 py-1 text-[10.5px] uppercase tracking-wider font-bold text-faint">{g.label}</div>
              {g.items.map(h => {
                const idx = hits.indexOf(h)
                const active = idx === selected
                return (
                  <button
                    key={`${h.kind}-${h.id}`}
                    type="button"
                    onClick={() => go(h)}
                    onMouseEnter={() => setSelected(idx)}
                    className={'w-full flex items-center gap-3 px-3 py-2 text-sm text-left ' + (active ? 'bg-canvas-2' : '')}
                  >
                    {h.kind === 'person'      && <User size={14} className="text-person flex-shrink-0" />}
                    {h.kind === 'role'        && <FileText size={14} className="text-role flex-shrink-0" />}
                    {h.kind === 'requisition' && <Briefcase size={14} className="text-role flex-shrink-0" />}
                    {h.kind === 'org'         && <Users size={14} className="text-muted flex-shrink-0" />}
                    <span className="flex-1 min-w-0">
                      <span className="font-medium truncate block">{h.label}</span>
                      <span className="text-xs text-faint truncate block">{h.sub}</span>
                    </span>
                  </button>
                )
              })}
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
