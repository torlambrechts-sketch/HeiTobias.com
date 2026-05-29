import { BrowserRouter, Route, Routes } from 'react-router-dom'
import { lazy, Suspense } from 'react'
import { Loader2 } from 'lucide-react'
import { HomePage } from './pages/Home.js'
import { EnvBoundary } from './components/EnvBoundary.js'
import { LocaleProvider } from './lib/i18n.js'
import { ModuleGate } from './components/ModuleGate.js'
import { ToastProvider } from './components/ui/Toast.js'
import { ErrorBoundary } from './components/ErrorBoundary.js'

// Code-split heavy routes (ITEM 6). HomePage stays eager because it's
// the landing entry point — everything else loads on navigation.
//
// All page files use named exports; lazy() expects a `default` so we
// adapt with .then(m => ({ default: m.X })). Vite's Rollup picks each
// up as a separate chunk; verified by cp6-code-split.test.ts and the
// `dist/assets/*.js` count after `npm run build`.
const PeoplePage                = lazy(() => import('./pages/People.js').then(m => ({ default: m.PeoplePage })))
const CandidateTakePage         = lazy(() => import('./pages/CandidateTake.js').then(m => ({ default: m.CandidateTakePage })))
const CandidateConsentsPage     = lazy(() => import('./pages/CandidateConsents.js').then(m => ({ default: m.CandidateConsentsPage })))
const RecruiterRequisitionPage  = lazy(() => import('./pages/RecruiterRequisition.js').then(m => ({ default: m.RecruiterRequisitionPage })))
const RequisitionsIndexPage     = lazy(() => import('./pages/RequisitionsIndex.js').then(m => ({ default: m.RequisitionsIndexPage })))
const EmployerActivationsPage   = lazy(() => import('./pages/EmployerActivations.js').then(m => ({ default: m.EmployerActivationsPage })))
const ManagerEmployeeDetailPage = lazy(() => import('./pages/ManagerEmployeeDetail.js').then(m => ({ default: m.ManagerEmployeeDetailPage })))
const ModelingAdminPage         = lazy(() => import('./pages/ModelingAdmin.js').then(m => ({ default: m.ModelingAdminPage })))
const WorkspaceAdminPage        = lazy(() => import('./pages/WorkspaceAdmin.js').then(m => ({ default: m.WorkspaceAdminPage })))
const AcceptInvitePage          = lazy(() => import('./pages/AcceptInvite.js').then(m => ({ default: m.AcceptInvitePage })))
const RoleProfilePage           = lazy(() => import('./pages/RoleProfile.js').then(m => ({ default: m.RoleProfilePage })))
const TeamDefinitionListPage    = lazy(() => import('./pages/TeamDefinitionList.js').then(m => ({ default: m.TeamDefinitionListPage })))
const TeamDefinitionNewPage     = lazy(() => import('./pages/TeamDefinitionNew.js').then(m => ({ default: m.TeamDefinitionNewPage })))
const TeamDefinitionRunPage     = lazy(() => import('./pages/TeamDefinitionRun.js').then(m => ({ default: m.TeamDefinitionRunPage })))
const DemoPage                  = lazy(() => import('./pages/Demo.js').then(m => ({ default: m.DemoPage })))
const RequisitionsListPage      = lazy(() => import('./pages/RequisitionsList.js').then(m => ({ default: m.RequisitionsListPage })))
const TeamPage                  = lazy(() => import('./pages/Team.js').then(m => ({ default: m.TeamPage })))
const MePage                    = lazy(() => import('./pages/Me.js').then(m => ({ default: m.MePage })))

function PageFallback() {
  return (
    <div className="min-h-screen flex items-center justify-center text-muted text-sm">
      <Loader2 size={18} className="animate-spin mr-2" /> Loading…
    </div>
  )
}

export function App() {
  return (
    <EnvBoundary>
      <LocaleProvider>
        <ToastProvider>
          <ErrorBoundary>
            <BrowserRouter>
              <Suspense fallback={<PageFallback />}>
                <Routes>
              <Route path="/" element={<HomePage />} />
              <Route path="/people" element={<PeoplePage />} />
              <Route path="/take/:token" element={<CandidateTakePage />} />
              <Route path="/me/:token" element={<CandidateConsentsPage />} />
              <Route path="/requisitions" element={<RequisitionsIndexPage />} />
              <Route path="/requisitions/:id" element={<RecruiterRequisitionPage />} />
              <Route path="/activations" element={<EmployerActivationsPage />} />
              <Route path="/employees/:id" element={<ManagerEmployeeDetailPage />} />
              <Route path="/modeling" element={<ModelingAdminPage />} />
              <Route path="/admin" element={<WorkspaceAdminPage />} />
              <Route path="/admin/accept-invite/:token" element={<AcceptInvitePage />} />
              <Route path="/roles/:id" element={<RoleProfilePage />} />
              <Route path="/roles/:id/:version" element={<RoleProfilePage />} />
              <Route path="/team-def" element={<ModuleGate moduleKey="team_definition"><TeamDefinitionListPage /></ModuleGate>} />
              <Route path="/team-def/new" element={<ModuleGate moduleKey="team_definition"><TeamDefinitionNewPage /></ModuleGate>} />
              <Route path="/team-def/runs/:id" element={<ModuleGate moduleKey="team_definition"><TeamDefinitionRunPage /></ModuleGate>} />
              {import.meta.env.DEV && (
                <Route path="/demo" element={<DemoPage />} />
              )}
              <Route path="/req" element={<RequisitionsListPage />} />
              <Route path="/team" element={<TeamPage />} />
              <Route path="/me" element={<MePage />} />
              <Route path="*" element={<NotFoundPage />} />
                </Routes>
              </Suspense>
            </BrowserRouter>
          </ErrorBoundary>
        </ToastProvider>
      </LocaleProvider>
    </EnvBoundary>
  )
}

// Designed 404 page. Replaces the previous catch-all redirect to "/"
// (which silently swallowed typos and made link rot invisible).
function NotFoundPage() {
  return (
    <main className="min-h-screen flex items-center justify-center px-4 bg-canvas">
      <div className="max-w-md text-center">
        <p className="text-[10.5px] uppercase tracking-wider font-bold text-muted mb-2">404</p>
        <h1 className="font-display text-3xl font-bold text-ink mb-3">Page not found</h1>
        <p className="text-sm text-muted leading-relaxed">
          The URL you visited does not match a route in this app. If you followed a link
          from inside the platform, something has rotted — please report it. Otherwise,
          double-check the URL.
        </p>
        <a href="/" className="inline-block mt-6 text-sm text-role hover:underline">← Back to home</a>
      </div>
    </main>
  )
}
