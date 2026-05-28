import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { PeoplePage } from './pages/People.js'
import { HomePage } from './pages/Home.js'
import { CandidateTakePage } from './pages/CandidateTake.js'
import { RecruiterRequisitionPage } from './pages/RecruiterRequisition.js'
import { EnvBoundary } from './components/EnvBoundary.js'

export function App() {
  return (
    <EnvBoundary>
      <BrowserRouter>
        <Routes>
          <Route path="/" element={<HomePage />} />
          <Route path="/people" element={<PeoplePage />} />
          <Route path="/take/:token" element={<CandidateTakePage />} />
          <Route path="/requisitions/:id" element={<RecruiterRequisitionPage />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </BrowserRouter>
    </EnvBoundary>
  )
}
