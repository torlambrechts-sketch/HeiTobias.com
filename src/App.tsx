import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { PeoplePage } from './pages/People.js'
import { HomePage } from './pages/Home.js'
import { CandidateTakePage } from './pages/CandidateTake.js'
import { CandidateConsentsPage } from './pages/CandidateConsents.js'
import { RecruiterRequisitionPage } from './pages/RecruiterRequisition.js'
import { EmployerActivationsPage } from './pages/EmployerActivations.js'
import { ManagerEmployeeDetailPage } from './pages/ManagerEmployeeDetail.js'
import { ModelingAdminPage } from './pages/ModelingAdmin.js'
import { WorkspaceAdminPage } from './pages/WorkspaceAdmin.js'
import { AcceptInvitePage } from './pages/AcceptInvite.js'
import { RoleProfilePage } from './pages/RoleProfile.js'
import { EnvBoundary } from './components/EnvBoundary.js'

export function App() {
  return (
    <EnvBoundary>
      <BrowserRouter>
        <Routes>
          <Route path="/" element={<HomePage />} />
          <Route path="/people" element={<PeoplePage />} />
          <Route path="/take/:token" element={<CandidateTakePage />} />
          <Route path="/me/:token" element={<CandidateConsentsPage />} />
          <Route path="/requisitions/:id" element={<RecruiterRequisitionPage />} />
          <Route path="/activations" element={<EmployerActivationsPage />} />
          <Route path="/employees/:id" element={<ManagerEmployeeDetailPage />} />
          <Route path="/modeling" element={<ModelingAdminPage />} />
          <Route path="/admin" element={<WorkspaceAdminPage />} />
          <Route path="/admin/accept-invite/:token" element={<AcceptInvitePage />} />
          <Route path="/roles/:id" element={<RoleProfilePage />} />
          <Route path="/roles/:id/:version" element={<RoleProfilePage />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </BrowserRouter>
    </EnvBoundary>
  )
}
