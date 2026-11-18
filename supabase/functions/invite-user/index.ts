import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (request.method !== 'POST') return respond({ error: 'Método não permitido.' }, 405)

  const projectUrl = Deno.env.get('SUPABASE_URL')
  const publicKey = Deno.env.get('SUPABASE_PUBLIC_KEY')
  const serviceKey = Deno.env.get('SUPABASE_SECRET_KEY')
  const redirectTo = Deno.env.get('APP_REDIRECT_URL')
  const authorization = request.headers.get('Authorization')
  if (!projectUrl || !publicKey || !serviceKey || !redirectTo || !authorization) {
    return respond({ error: 'A função de convite não está configurada.' }, 500)
  }

  try {
    const caller = createClient(projectUrl, publicKey, { global: { headers: { Authorization: authorization } } })
    const { data: userData, error: userError } = await caller.auth.getUser()
    if (userError || !userData.user) return respond({ error: 'Sessão inválida. Entre novamente.' }, 401)
    const { data: profile, error: profileError } = await caller.rpc('finance_my_profile')
    if (profileError || profile?.role !== 'owner' || profile?.active !== true) {
      return respond({ error: 'Somente Pablo pode convidar usuários.' }, 403)
    }

    const body = await request.json()
    const email = String(body.email || '').trim().toLowerCase()
    const displayName = String(body.displayName || '').trim().slice(0, 80)
    const canViewValues = body.canViewValues === true
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return respond({ error: 'Informe um e-mail válido.' }, 400)

    const { error: inviteRowError } = await caller.rpc('finance_admin_create_invite', {
      p_email: email,
      p_display_name: displayName,
      p_can_view_values: canViewValues,
    })
    if (inviteRowError) return respond({ error: inviteRowError.message }, 400)

    const admin = createClient(projectUrl, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } })
    const { error: sendError } = await admin.auth.admin.inviteUserByEmail(email, { redirectTo })
    if (sendError) {
      await caller.rpc('finance_admin_cancel_invite', { p_email: email })
      return respond({ error: sendError.message }, 400)
    }
    return respond({ ok: true, message: `Convite enviado para ${email}.` }, 200)
  } catch (error) {
    return respond({ error: error instanceof Error ? error.message : 'Falha ao enviar o convite.' }, 500)
  }
})

function respond(body: Record<string, unknown>, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
