import { ShieldAlert } from 'lucide-react'

// THE LOAD-BEARING UI GUARDRAIL. Per the closure prompt §"OVERRIDING
// PRINCIPLES" (CLAUDE-CODE-TEAM-DEFINITION-PROMPT.md) and SCIENCE-SPEC
// §7: peer-personality rating must be refused at the SCHEMA layer AND
// at the UI layer — and the UI version must be visible body copy, NOT
// a tooltip the evaluator can dismiss.
//
// This component renders as a prominent body block above every Stage 2
// rating form. The schema CHECK (chk_team_def_evaluations_no_peer_personality
// in 20260529095459_team_definition_cp31_schema.sql) is the second
// belt; this is the first one.
export function SurveillanceGuardrail() {
  return (
    <div
      data-test="surveillance-guardrail"
      className="rounded border border-rust border-l-4 border-l-rust bg-reject-bg p-4 mb-6 flex items-start gap-3 text-sm leading-relaxed"
    >
      <span className="text-[10.5px] uppercase tracking-wider font-bold px-2 py-1 rounded bg-white text-rust border border-rust/30 inline-flex items-center gap-1.5 flex-shrink-0 whitespace-nowrap">
        <ShieldAlert size={13} /> Guardrail
      </span>
      <div className="text-ink/90">
        You are rating <strong>the role</strong> — its tasks, competency weights, trait targets
        for the role context, and context factors. <strong>You are not rating each other.</strong>{' '}
        Peer rating of any named person's personality is blocked at the schema level{' '}
        (<span className="font-mono text-xs">SCIENCE-SPEC §7; PHASE0-SPEC §2.7</span>). Team
        composition signals are derived only from each member's own validated profile, never
        from anyone else's opinion about them.
      </div>
    </div>
  )
}
