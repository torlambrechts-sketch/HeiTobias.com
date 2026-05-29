import { type ReactNode } from 'react'
import { Loader2, ShieldOff } from 'lucide-react'
import { useOrgModule } from '../lib/useOrgModule.js'
import { Shell } from './Shell.js'
import { Card, CardBody } from './ui/card.js'

// Wraps a route element so that, if an admin has flipped the module
// off for this org, navigating here shows a clear "module disabled"
// message instead of the surface. The DB trigger
// _check_org_modules_availability already enforces availability tri-state;
// this wrapper is the visible-to-the-user complement.
export function ModuleGate({ moduleKey, children }: { moduleKey: string; children: ReactNode }) {
  const enabled = useOrgModule(moduleKey)
  if (enabled === undefined) {
    return (
      <Shell breadcrumb={<span>Loading…</span>}>
        <div className="text-faint text-sm flex items-center gap-2"><Loader2 size={14} className="animate-spin" /> Checking module access…</div>
      </Shell>
    )
  }
  if (!enabled) {
    return (
      <Shell breadcrumb={<span>Module disabled</span>}>
        <Card data-test="module-disabled">
          <CardBody className="flex items-start gap-3">
            <ShieldOff size={20} className="text-rust flex-shrink-0 mt-0.5" />
            <div className="text-sm">
              <div className="font-semibold mb-1">This module is disabled for your org.</div>
              <p className="text-muted leading-relaxed">
                The <code className="font-mono">{moduleKey}</code> module is currently turned off.
                Contact your admin to enable it — the change happens in <code>Workspace admin → Modules</code>
                and is audited per the org's decision-artefact policy.
              </p>
            </div>
          </CardBody>
        </Card>
      </Shell>
    )
  }
  return <>{children}</>
}
