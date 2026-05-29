// Email service — application-level helper that builds + enqueues
// transactional emails. Templates render here (so we keep i18n + brand
// in one place); transport happens out-of-band via the operator's
// SMTP worker reading email_outbox.
//
// Template inventory (matches the spec):
//   * user_invite           — invitation to join an org
//   * candidate_take_token  — candidate's magic link
//   * password_reset        — Supabase Auth handles its own, but we
//                              wrap the outgoing for consistent brand
//   * email_verification    — same; wrapped
//   * consent_revoke_ack    — confirmation after a consent revoke
//   * admin_pending_invite  — admin reminder for unaccepted invites
//   * admin_leave_request   — admin notification of a /me leave-request
//
// Localization: we read the org's locale_default + the recipient's
// preferred locale (when known) and pick the rendered strings from
// src/i18n/<locale>.json. Per the i18n closure-pass discipline, Nordic
// translations remain HANDOFF until a localiser fills them in; en.json
// is the fallback.

import type { SupabaseClient } from '@supabase/supabase-js'
import en from '../i18n/en.json'

type Locale = 'en' | 'nb-NO' | 'sv-SE' | 'da-DK'

export type EmailTemplateKey =
  | 'user_invite'
  | 'candidate_take_token'
  | 'password_reset'
  | 'email_verification'
  | 'consent_revoke_ack'
  | 'admin_pending_invite'
  | 'admin_leave_request'

interface RenderInput {
  org_name: string
  org_accent_color?: string
  org_logo_url?: string
  recipient_name?: string
  app_url: string
  data: Record<string, string>
}

interface Rendered { subject: string; text: string; html: string }

// Fallback English subject + body for each template.
// Nordic translations are HANDOFF; the localiser fills i18n/<locale>.json
// when they engage. Until then the fallback chain en → key keeps emails
// readable.
const FALLBACK_EN: Record<EmailTemplateKey, { subject: string; text: string; html: string }> = {
  user_invite: {
    subject: 'You\'re invited to {{org_name}} on HeiTobias',
    text:
      'Hi{{name_suffix}},\n\n' +
      '{{inviter_name}} has invited you to join {{org_name}} on HeiTobias.\n\n' +
      'Accept your invite: {{accept_url}}\n\n' +
      'This link expires in 7 days. If you have questions, reply to this email\n' +
      '({{reply_to}}) and your org admin will get back to you.\n\n' +
      '— {{org_name}}',
    html:
      '<p>Hi{{name_suffix}},</p>' +
      '<p><strong>{{inviter_name}}</strong> has invited you to join <strong>{{org_name}}</strong> on HeiTobias.</p>' +
      '<p><a href="{{accept_url}}" style="background:{{accent}};color:#fff;padding:10px 16px;border-radius:6px;text-decoration:none">Accept your invite</a></p>' +
      '<p style="color:#888;font-size:12px">This link expires in 7 days. Reply to <a href="mailto:{{reply_to}}">{{reply_to}}</a> with questions.</p>' +
      '<p>— {{org_name}}</p>',
  },
  candidate_take_token: {
    subject: 'Your assessment for {{role_title}} at {{org_name}}',
    text:
      'Hi{{name_suffix}},\n\n' +
      'You\'ve been invited to complete an assessment for the {{role_title}} role at {{org_name}}.\n\n' +
      'Start: {{take_url}}\n\n' +
      'The session has four parts: personality, cognitive, values, and structured-interview prep.\n' +
      'Honest length: 45-75 minutes. You can save and resume across parts.\n\n' +
      'Your responses are purpose-limited to this hiring decision and you can revoke consent\n' +
      'at any time. EU-hosted, audited, your data is yours.\n\n' +
      '— {{org_name}}',
    html:
      '<p>Hi{{name_suffix}},</p>' +
      '<p>You\'ve been invited to complete an assessment for the <strong>{{role_title}}</strong> role at <strong>{{org_name}}</strong>.</p>' +
      '<p><a href="{{take_url}}" style="background:{{accent}};color:#fff;padding:10px 16px;border-radius:6px;text-decoration:none">Start the assessment</a></p>' +
      '<p>The session has four parts: personality, cognitive, values, structured-interview prep. Honest length: 45-75 minutes; save-and-resume across parts.</p>' +
      '<p style="color:#888;font-size:12px">Your responses are purpose-limited to this hiring decision; you can revoke consent at any time. EU-hosted, audited, your data is yours.</p>' +
      '<p>— {{org_name}}</p>',
  },
  password_reset: {
    subject: 'Reset your HeiTobias password',
    text: 'Click to reset your password: {{reset_url}}\n\nThis link expires in 1 hour.\n\n— HeiTobias',
    html: '<p><a href="{{reset_url}}" style="background:{{accent}};color:#fff;padding:10px 16px;border-radius:6px;text-decoration:none">Reset your password</a></p><p style="color:#888;font-size:12px">This link expires in 1 hour.</p>',
  },
  email_verification: {
    subject: 'Verify your email for HeiTobias',
    text: 'Verify your email: {{verify_url}}\n\nThis link expires in 24 hours.',
    html: '<p><a href="{{verify_url}}" style="background:{{accent}};color:#fff;padding:10px 16px;border-radius:6px;text-decoration:none">Verify email</a></p><p style="color:#888;font-size:12px">This link expires in 24 hours.</p>',
  },
  consent_revoke_ack: {
    subject: 'Consent revoked — {{purpose}}',
    text:
      'Hi{{name_suffix}},\n\n' +
      'Confirmation: your consent for "{{purpose}}" granted to {{granted_to}} has been revoked\n' +
      'as of {{revoked_at}}.\n\n' +
      'Effects:\n' +
      '  • {{granted_to}} loses visibility of this data immediately.\n' +
      '  • Previously generated artefacts remain in the audit log per AI Act Art. 12\n' +
      '    but become non-displayable.\n\n' +
      '— HeiTobias',
    html:
      '<p>Hi{{name_suffix}},</p>' +
      '<p>Confirmation: your consent for <strong>{{purpose}}</strong> granted to <strong>{{granted_to}}</strong> has been revoked as of {{revoked_at}}.</p>' +
      '<p>Effects: {{granted_to}} loses visibility immediately. Previously generated artefacts remain in the audit log per AI Act Art. 12 but become non-displayable.</p>',
  },
  admin_pending_invite: {
    subject: '{{n_pending}} pending invite{{plural}} at {{org_name}}',
    text: 'You have {{n_pending}} pending user invite{{plural}}. Review at {{admin_url}}.',
    html: '<p>You have <strong>{{n_pending}}</strong> pending user invite{{plural}}.</p><p><a href="{{admin_url}}">Open admin →</a></p>',
  },
  admin_leave_request: {
    subject: '{{member_name}} requested to leave {{org_name}}',
    text:
      '{{member_name}} has requested to leave {{org_name}}.\n' +
      'Grace period: 7 days, ending {{grace_until}}.\n' +
      'Reason: {{rationale_excerpt}}\n\n' +
      'Open admin: {{admin_url}}',
    html:
      '<p><strong>{{member_name}}</strong> has requested to leave <strong>{{org_name}}</strong>.</p>' +
      '<p>Grace period: 7 days, ending <strong>{{grace_until}}</strong>.</p>' +
      '<p>Reason: <em>{{rationale_excerpt}}</em></p>' +
      '<p><a href="{{admin_url}}">Open admin →</a></p>',
  },
}

function interpolate(s: string, vars: Record<string, string>): string {
  return s.replace(/\{\{(\w+)\}\}/g, (_, k) => vars[k] ?? '')
}

export function render(template: EmailTemplateKey, locale: Locale, input: RenderInput): Rendered {
  // Lookup chain: i18n/<locale>.json[email.<template>.subject] → en.json → FALLBACK_EN
  // (Nordic locales currently empty — HANDOFF — so the chain falls through.)
  const enFallback = FALLBACK_EN[template]
  const enKeys = en as Record<string, string>
  const subject = enKeys[`email.${template}.subject`] ?? enFallback.subject
  const text    = enKeys[`email.${template}.text`]    ?? enFallback.text
  const html    = enKeys[`email.${template}.html`]    ?? enFallback.html

  const vars: Record<string, string> = {
    org_name:     input.org_name,
    accent:       input.org_accent_color ?? '#3f7d5a',
    logo_url:     input.org_logo_url ?? '',
    name_suffix:  input.recipient_name ? ` ${input.recipient_name}` : '',
    app_url:      input.app_url,
    reply_to:     input.data['reply_to'] ?? '',
    ...input.data,
  }
  void locale  // wired through to future i18n lookup; en is the only populated dict today
  return {
    subject: interpolate(subject, vars),
    text:    interpolate(text,    vars),
    html:    interpolate(html,    vars),
  }
}

// Enqueue a rendered email into the outbox. Returns the row id.
export async function sendEmail(
  supabase: SupabaseClient,
  args: {
    org_id: string
    to_email: string
    to_name?: string
    template: EmailTemplateKey
    locale: Locale
    input: RenderInput
    triggered_by_action?: string
  },
): Promise<{ id: string }> {
  const r = render(args.template, args.locale, args.input)
  const { data, error } = await supabase.rpc('email_enqueue' as never, {
    p_org_id: args.org_id,
    p_to_email: args.to_email,
    p_to_name: args.to_name ?? null,
    p_template_key: args.template,
    p_locale: args.locale,
    p_subject: r.subject,
    p_body_text: r.text,
    p_body_html: r.html,
    p_render_data: args.input.data,
    p_triggered_by_action: args.triggered_by_action ?? null,
  } as never)
  if (error) throw new Error(error.message)
  return { id: data as unknown as string }
}
