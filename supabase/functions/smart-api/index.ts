import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-supabase-api-version',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (request.method !== 'POST') return respond({ error: 'Método não permitido.' }, 405)

  const projectUrl = Deno.env.get('SUPABASE_URL')
  // Supabase supplies these keys in the Edge Functions runtime. Keep legacy
  // custom names as fallbacks for projects that already configured them.
  const publicKey = Deno.env.get('SUPABASE_ANON_KEY') || Deno.env.get('SUPABASE_PUBLIC_KEY')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || Deno.env.get('SUPABASE_SECRET_KEY')
  const authorization = request.headers.get('Authorization')
  if (!projectUrl || !publicKey || !serviceKey || !authorization) {
    return respond({ error: 'A função de gerenciamento de contas não está configurada.' }, 500)
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
    const admin = createClient(projectUrl, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } })

    if (typeof body.password !== 'string' || body.password.length < 12 || body.password.length > 128) {
      return respond({ error: 'A senha deve ter entre 12 e 128 caracteres.' }, 400)
    }

    if (body.action === 'reset-password') {
      const userId = String(body.userId || '')
      const { data: members, error: membersError } = await caller.rpc('finance_admin_list_members')
      if (membersError) return respond({ error: membersError.message }, 400)
      const target = (members || []).find((member: { user_id: string; role: string }) => member.user_id === userId && member.role === 'member')
      if (!target) return respond({ error: 'Conta de convidado não encontrada.' }, 404)

      const { error } = await admin.auth.admin.updateUserById(userId, { password: body.password })
      if (error) return respond({ error: error.message }, 400)
      return respond({ ok: true, message: 'Senha atualizada. Avise a nova senha à pessoa por um canal privado.' }, 200)
    }

    if (body.action !== 'create') return respond({ error: 'Ação de gerenciamento inválida.' }, 400)

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

    const { error: createError } = await admin.auth.admin.createUser({
      email,
      password: body.password,
      email_confirm: true,
    })
    if (createError) {
      await caller.rpc('finance_admin_cancel_invite', { p_email: email })
      return respond({ error: createError.message }, 400)
    }
    return respond({ ok: true, message: `Conta criada para ${email}. Entregue a senha inicial à pessoa por um canal privado.` }, 200)
  } catch (error) {
    return respond({ error: error instanceof Error ? error.message : 'Falha ao gerenciar a conta.' }, 500)
  }
})

function respond(body: Record<string, unknown>, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
