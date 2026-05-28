import { Link, NavLink, useLocation } from 'react-router-dom'
import { type ReactNode } from 'react'
import {
  Bell,
  Briefcase,
  Building2,
  Check,
  ChevronDown,
  ChevronLeft,
  Home,
  LayoutGrid,
  Settings,
  TrendingUp,
  Users,
} from 'lucide-react'
import { cn } from '../lib/cn.js'

/**
 * The three-tier canonical app shell (DESIGN.md §2):
 *   [ 60px dark-green icon rail ] [ 220px cream section nav ] [ content ]
 * Mobile/narrow viewports collapse the section nav.
 */
export function Shell({
  breadcrumb,
  children,
  signedInLabel,
  orgLabel = 'HeiTobias',
}: {
  breadcrumb: ReactNode
  children: ReactNode
  signedInLabel?: string | null | undefined
  orgLabel?: string
}) {
  return (
    <div className="grid grid-cols-[60px_1fr] lg:grid-cols-[60px_220px_1fr] min-h-screen">
      <IconRail />
      <SectionNav />
      <main className="flex flex-col min-w-0">
        <AppBar breadcrumb={breadcrumb} orgLabel={orgLabel} signedInLabel={signedInLabel} />
        <div className="px-8 py-8 max-w-[1280px] w-full">{children}</div>
      </main>
    </div>
  )
}

function IconRail() {
  const items = [
    { icon: Home, to: '/' },
    { icon: Briefcase, to: '/requisitions/a3000000-0000-0000-0000-000000000001' },
    { icon: Users, to: '/people' },
    { icon: TrendingUp, to: '/growth' },
    { icon: LayoutGrid, to: '/insights' },
    { icon: Building2, to: '/company' },
  ]
  return (
    <nav className="bg-rail flex flex-col items-center py-4 sticky top-0 h-screen">
      <div className="w-[34px] h-[34px] rounded-lg bg-white flex items-center justify-center font-display font-bold text-xl text-rail mb-4">
        T
      </div>
      {items.map(({ icon: Icon, to }, i) => (
        <RailLink key={i} to={to}>
          <Icon size={21} strokeWidth={2} />
        </RailLink>
      ))}
      <div className="flex-1" />
      <RailLink to="/settings">
        <Settings size={21} strokeWidth={2} />
      </RailLink>
      <div className="w-[34px] h-[34px] rounded-full bg-forest text-white border-2 border-white/25 flex items-center justify-center font-bold text-xs mt-2">
        SH
      </div>
    </nav>
  )
}

function RailLink({ to, children }: { to: string; children: ReactNode }) {
  const loc = useLocation()
  const active = loc.pathname === to || (to !== '/' && loc.pathname.startsWith(to))
  return (
    <Link
      to={to}
      className={cn(
        'relative w-10 h-10 rounded-lg flex items-center justify-center mb-1 transition-colors',
        active ? 'bg-white text-rail' : 'text-white/60 hover:text-white hover:bg-white/10',
      )}
    >
      {active && <span className="absolute -left-4 top-2 bottom-2 w-[3px] rounded-sm bg-white" />}
      {children}
    </Link>
  )
}

function SectionNav() {
  return (
    <aside className="hidden lg:flex bg-canvas border-r border-line sticky top-0 h-screen overflow-auto flex-col">
      <div className="px-5 pt-5 pb-4 flex items-center justify-between">
        <span className="font-display text-2xl font-bold tracking-tight">HeiTobias</span>
        <ChevronLeft size={15} className="text-faint" />
      </div>
      <nav className="px-3.5 pb-5 flex flex-col gap-4">
        <NavGroup icon={Home} title="Dashboard" />
        <NavGroup icon={Briefcase} title="Hiring" defaultOpen>
          <NavSub to="/requisitions/a3000000-0000-0000-0000-000000000001">Requisitions</NavSub>
          <NavSub to="#">Role library</NavSub>
          <NavSub to="#">Team-based definition</NavSub>
        </NavGroup>
        <NavGroup icon={Users} title="People" defaultOpen>
          <NavSub to="/people">All people</NavSub>
          <NavSub to="#">My team</NavSub>
          <NavSub to="#">Candidates</NavSub>
        </NavGroup>
        <NavGroup icon={TrendingUp} title="Growth">
          <NavSub to="#">Re-fit & growth</NavSub>
          <NavSub to="#">Team composition</NavSub>
          <NavSub to="#">1:1 prep</NavSub>
        </NavGroup>
        <NavGroup icon={LayoutGrid} title="Insights">
          <NavSub to="#">Fit trends</NavSub>
          <NavSub to="#">Retention signals</NavSub>
        </NavGroup>
        <NavGroup icon={Building2} title="Company">
          <NavSub to="#">Settings</NavSub>
        </NavGroup>
      </nav>
    </aside>
  )
}

function NavGroup({
  icon: Icon,
  title,
  defaultOpen = false,
  children,
}: {
  icon: typeof Home
  title: string
  defaultOpen?: boolean
  children?: ReactNode
}) {
  return (
    <div>
      <div className="flex items-center gap-2.5 px-2 pb-2 text-ink">
        <Icon size={15} strokeWidth={2} />
        <span className="text-[11.5px] font-bold uppercase tracking-wider">{title}</span>
        {children && <ChevronDown size={15} className="ml-auto text-faint" />}
      </div>
      {children && defaultOpen && <div className="flex flex-col">{children}</div>}
    </div>
  )
}

function NavSub({ to, children }: { to: string; children: ReactNode }) {
  return (
    <NavLink
      to={to}
      className={({ isActive }) =>
        cn(
          'block pl-7 pr-2 py-1.5 text-[13px] font-medium rounded relative',
          'before:content-[""] before:absolute before:left-3.5 before:top-[13px] before:w-1 before:h-1 before:rounded-full',
          isActive
            ? 'text-ink font-bold before:bg-green'
            : 'text-muted before:bg-faint hover:text-ink hover:bg-canvas-2',
        )
      }
    >
      {children}
    </NavLink>
  )
}

function AppBar({
  breadcrumb,
  orgLabel,
  signedInLabel,
}: {
  breadcrumb: ReactNode
  orgLabel: string
  signedInLabel?: string | null | undefined
}) {
  return (
    <div className="flex items-center gap-3.5 px-8 py-4 border-b border-line">
      <div className="text-sm text-muted flex items-center gap-2">{breadcrumb}</div>
      <div className="ml-auto flex items-center gap-4">
        <div className="flex items-center gap-2 text-xs font-bold uppercase tracking-wider text-ink">
          <Building2 size={15} className="text-forest" /> {orgLabel}
        </div>
        <Check size={18} className="text-muted" />
        <Bell size={18} className="text-muted" />
        <div className="w-9 h-9 rounded-full bg-forest text-white flex items-center justify-center font-bold text-[13px]">
          {signedInLabel ? signedInLabel.slice(0, 2).toUpperCase() : 'SH'}
        </div>
      </div>
    </div>
  )
}
