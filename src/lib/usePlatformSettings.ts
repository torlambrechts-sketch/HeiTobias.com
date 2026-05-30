import { useEffect, useState } from 'react'
import { browserSupabase } from './browser-supabase.js'

// Public platform settings (legal contact + review status). Read via the
// anon-safe platform_settings_public() RPC — only the columns legal pages
// render are exposed by that function.
export interface PublicPlatformSettings {
  platform_legal_entity_name: string | null
  platform_legal_entity_address: string | null
  dpo_contact_name: string | null
  dpo_contact_email: string | null
  support_email: string | null
  legal_review_status: 'pending' | 'current'
  legal_reviewer_name: string | null
  legal_reviewed_at: string | null
}

export function usePlatformSettings(): PublicPlatformSettings | null {
  const supabase = browserSupabase()
  const [settings, setSettings] = useState<PublicPlatformSettings | null>(null)
  useEffect(() => {
    let live = true
    void (async () => {
      const { data, error } = await supabase.rpc('platform_settings_public' as never)
      if (!live || error) return
      setSettings(data as unknown as PublicPlatformSettings)
    })()
    return () => { live = false }
  }, [supabase])
  return settings
}
