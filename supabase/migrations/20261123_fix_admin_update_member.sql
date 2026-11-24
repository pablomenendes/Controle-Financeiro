-- Repara a RPC usada pelo painel de acessos para atualizar permissões.
-- Não altera linhas de usuários nem dados financeiros.
begin;

drop function if exists public.finance_admin_update_member(uuid, boolean, boolean);
drop function if exists public.finance_admin_update_member(uuid, boolean, boolean, text, boolean);

create function public.finance_admin_update_member(
  p_user_id uuid,
  p_can_view_values boolean,
  p_can_view_card_loans boolean,
  p_loan_borrower text,
  p_active boolean
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
begin
  if not exists (
    select 1
    from public.finance_profiles
    where user_id = auth.uid() and active and role = 'owner'
  ) then
    raise exception 'Somente o responsável pode alterar acessos.';
  end if;

  if coalesce(p_can_view_card_loans, false)
     and not coalesce(p_can_view_values, false)
     and nullif(trim(coalesce(p_loan_borrower, '')), '') is null then
    raise exception 'Escolha a pessoa vinculada aos empréstimos no cartão.';
  end if;

  update public.finance_profiles
  set can_view_values = coalesce(p_can_view_values, false),
      can_view_card_loans = coalesce(p_can_view_card_loans, false),
      loan_borrower = trim(coalesce(p_loan_borrower, '')),
      active = coalesce(p_active, false),
      updated_at = now()
  where user_id = p_user_id and role = 'member';

  if not found then
    raise exception 'Usuário convidado não encontrado.';
  end if;
end;
$$;

revoke all on function public.finance_admin_update_member(uuid, boolean, boolean, text, boolean)
  from public, anon, authenticated;
grant execute on function public.finance_admin_update_member(uuid, boolean, boolean, text, boolean)
  to authenticated;

-- Atualiza a lista de funções que o PostgREST disponibiliza para o site.
notify pgrst, 'reload schema';
commit;
