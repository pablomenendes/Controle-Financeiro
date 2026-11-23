-- Controle Financeiro: authentication, invited members and shared dashboard state.
-- Run this in the Supabase SQL Editor before configuring the frontend.

create extension if not exists pgcrypto;

create table if not exists public.finance_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  display_name text not null default '',
  role text not null check (role in ('owner', 'member')),
  can_view_values boolean not null default false,
  can_view_card_loans boolean not null default false,
  loan_borrower text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.finance_invites (
  email text primary key,
  display_name text not null default '',
  role text not null default 'member' check (role in ('owner', 'member')),
  can_view_values boolean not null default false,
  can_view_card_loans boolean not null default false,
  loan_borrower text not null default '',
  invited_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  consumed_at timestamptz
);

create table if not exists public.finance_state (
  id boolean primary key default true check (id = true),
  payload jsonb not null default '{"transactions":[],"settings":{},"rules":[],"budgets":[],"accounts":[],"recurrences":[],"goals":[],"importBatches":[]}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);

alter table public.finance_profiles enable row level security;
alter table public.finance_invites enable row level security;
alter table public.finance_state enable row level security;
alter table public.finance_profiles add column if not exists can_view_card_loans boolean not null default false;
alter table public.finance_profiles add column if not exists loan_borrower text not null default '';
alter table public.finance_invites add column if not exists can_view_card_loans boolean not null default false;
alter table public.finance_invites add column if not exists loan_borrower text not null default '';

-- The app uses only the guarded RPC functions below. No client can query tables directly.
revoke all on public.finance_profiles, public.finance_invites, public.finance_state from public, anon, authenticated;

create or replace function public.finance_redact_values(p_doc jsonb)
returns jsonb
language sql
immutable
set search_path = pg_catalog, public
as $$
  select case jsonb_typeof(p_doc)
    when 'object' then (
      select coalesce(jsonb_object_agg(key,
        case when lower(key) = any(array['amount','balance','initialbalance','currentbalance','limit','target','value','savingsrate','savingrate','rate','percent','percentage'])
          then 'null'::jsonb
          else public.finance_redact_values(value)
        end
      ), '{}'::jsonb)
      from jsonb_each(p_doc)
    )
    when 'array' then (
      select coalesce(jsonb_agg(public.finance_redact_values(value)), '[]'::jsonb)
      from jsonb_array_elements(p_doc)
    )
    else p_doc
  end;
$$;

create or replace function public.finance_handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  invitation public.finance_invites%rowtype;
begin
  if new.email is null then return new; end if;

  select * into invitation
    from public.finance_invites
    where email = lower(new.email) and consumed_at is null;

  -- Self-registration without an approved invitation creates no dashboard access.
  if not found then return new; end if;

  insert into public.finance_profiles(user_id, email, display_name, role, can_view_values, can_view_card_loans, loan_borrower, active)
  values (
    new.id,
    lower(new.email),
    coalesce(nullif(invitation.display_name, ''), split_part(new.email, '@', 1)),
    invitation.role,
    invitation.can_view_values,
    invitation.can_view_card_loans,
    invitation.loan_borrower,
    true
  )
  on conflict (user_id) do update set
    email = excluded.email,
    display_name = excluded.display_name,
    role = excluded.role,
    can_view_values = excluded.can_view_values,
    can_view_card_loans = excluded.can_view_card_loans,
    loan_borrower = excluded.loan_borrower,
    active = true,
    updated_at = now();

  update public.finance_invites set consumed_at = now() where email = lower(new.email);
  return new;
end;
$$;

drop trigger if exists finance_auth_user_created on auth.users;
create trigger finance_auth_user_created
  after insert on auth.users
  for each row execute function public.finance_handle_new_user();

create or replace function public.finance_my_profile()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare result jsonb;
begin
  select jsonb_build_object(
    'user_id', p.user_id,
    'email', p.email,
    'display_name', p.display_name,
    'role', p.role,
    'can_view_values', p.can_view_values,
    'can_view_card_loans', p.can_view_card_loans,
    'loan_borrower', p.loan_borrower,
    'active', p.active
  ) into result
  from public.finance_profiles p
  where p.user_id = auth.uid() and p.active;

  if result is null then raise exception 'Acesso não autorizado ou conta desativada.'; end if;
  return result;
end;
$$;

create or replace function public.finance_normalize_category(p_value text)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select regexp_replace(translate(lower(coalesce(p_value,'')), 'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc'), '[^a-z0-9]', '', 'g');
$$;

create or replace function public.finance_get_state()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare member public.finance_profiles%rowtype; payload jsonb; state_updated_at timestamptz; visible_loans jsonb;
begin
  select * into member from public.finance_profiles where user_id = auth.uid() and active;
  if not found then raise exception 'Acesso não autorizado ou conta desativada.'; end if;
  select s.payload, s.updated_at into payload, state_updated_at from public.finance_state s where s.id = true;
  if not coalesce(member.can_view_values, false) and coalesce(member.can_view_card_loans, false) then
    select coalesce(jsonb_agg(jsonb_build_object(
      'type',loan->'type','card',loan->'card','category',loan->'category','borrower',loan->'borrower',
      'reimbursed',loan->'reimbursed','projected',loan->'projected','amount',loan->'amount',
      'date',loan->'date','statementDate',loan->'statementDate','cardDueDate',loan->'cardDueDate',
      'installmentNumber',loan->'installmentNumber','installmentTotal',loan->'installmentTotal',
      'repaidDate',loan->'repaidDate','description',loan->'description','cardName',loan->'cardName'
    ) order by loan->>'date'), '[]'::jsonb) into visible_loans
    from jsonb_array_elements(coalesce(payload->'transactions','[]'::jsonb)) as entry(loan)
    where loan->>'type' = 'out'
      and lower(coalesce(loan->>'card','false')) = 'true'
      and public.finance_normalize_category(loan->>'category') = 'emprestimo'
      and nullif(trim(member.loan_borrower),'') is not null
      and lower(trim(coalesce(loan->>'borrower',''))) = lower(trim(member.loan_borrower));
    payload := jsonb_build_object('transactions', coalesce(visible_loans,'[]'::jsonb), 'settings','{}'::jsonb, 'rules','[]'::jsonb, 'budgets','[]'::jsonb, 'accounts','[]'::jsonb, 'recurrences','[]'::jsonb, 'goals','[]'::jsonb, 'importBatches','[]'::jsonb);
  elsif not coalesce(member.can_view_values, false) then
    payload := public.finance_redact_values(payload);
  end if;
  return jsonb_build_object(
    'profile', jsonb_build_object('display_name',member.display_name,'role',member.role,'can_view_values',member.can_view_values,'can_view_card_loans',member.can_view_card_loans),
    'payload', coalesce(payload, '{}'::jsonb),
    'updated_at', state_updated_at
  );
end;
$$;

drop function if exists public.finance_save_state(jsonb);
create function public.finance_save_state(p_payload jsonb, p_expected_updated_at timestamptz default null)
returns timestamptz
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare member public.finance_profiles%rowtype; saved_at timestamptz; current_updated_at timestamptz;
begin
  select * into member from public.finance_profiles where user_id = auth.uid() and active;
  if not found then raise exception 'Acesso não autorizado ou conta desativada.'; end if;
  if not member.can_view_values then raise exception 'Seu acesso é somente leitura e não permite alterar os dados financeiros.'; end if;
  if jsonb_typeof(p_payload) <> 'object' then raise exception 'Formato de dados inválido.'; end if;

  perform pg_advisory_xact_lock(hashtext('public.finance_state'));
  select updated_at into current_updated_at from public.finance_state where id = true for update;
  if p_expected_updated_at is distinct from current_updated_at then
    raise exception 'Os dados foram atualizados em outro dispositivo. Atualize a página antes de salvar novamente.';
  end if;

  insert into public.finance_state (id, payload, updated_at, updated_by)
  values (true, p_payload, now(), auth.uid())
  on conflict (id) do update set payload = excluded.payload, updated_at = excluded.updated_at, updated_by = excluded.updated_by
  returning updated_at into saved_at;
  return saved_at;
end;
$$;

create or replace function public.finance_admin_list_members()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare result jsonb;
begin
  if not exists (select 1 from public.finance_profiles where user_id = auth.uid() and active and role = 'owner') then
    raise exception 'Somente Pablo, como responsável, pode gerenciar acessos.';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'user_id',user_id,'email',email,'display_name',display_name,'role',role,
    'can_view_values',can_view_values,'can_view_card_loans',can_view_card_loans,'loan_borrower',loan_borrower,'active',active,'created_at',created_at
  ) order by role, display_name), '[]'::jsonb) into result
  from public.finance_profiles;
  return result;
end;
$$;

drop function if exists public.finance_admin_create_invite(text,text,boolean);
create function public.finance_admin_create_invite(p_email text, p_display_name text, p_can_view_values boolean, p_can_view_card_loans boolean, p_loan_borrower text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare clean_email text := lower(trim(p_email));
begin
  if not exists (select 1 from public.finance_profiles where user_id = auth.uid() and active and role = 'owner') then
    raise exception 'Somente o responsável pode convidar usuários.';
  end if;
  if coalesce(p_can_view_card_loans,false) and not coalesce(p_can_view_values,false) and nullif(trim(coalesce(p_loan_borrower,'')),'') is null then
    raise exception 'Escolha a pessoa vinculada aos empréstimos no cartão.';
  end if;
  if clean_email !~* '^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$' then raise exception 'Informe um e-mail válido.'; end if;
  if exists (select 1 from public.finance_profiles where email = clean_email and active) then raise exception 'Este usuário já tem acesso.'; end if;

  insert into public.finance_invites(email, display_name, role, can_view_values, can_view_card_loans, loan_borrower, invited_by, consumed_at)
  values(clean_email, trim(coalesce(p_display_name,'')), 'member', coalesce(p_can_view_values,false), coalesce(p_can_view_card_loans,false), trim(coalesce(p_loan_borrower,'')), auth.uid(), null)
  on conflict(email) do update set
    display_name = excluded.display_name,
    can_view_values = excluded.can_view_values,
    can_view_card_loans = excluded.can_view_card_loans,
    loan_borrower = excluded.loan_borrower,
    invited_by = excluded.invited_by,
    created_at = now(),
    consumed_at = null;
end;
$$;

drop function if exists public.finance_admin_update_member(uuid,boolean,boolean);
create function public.finance_admin_update_member(p_user_id uuid, p_can_view_values boolean, p_can_view_card_loans boolean, p_loan_borrower text, p_active boolean)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
begin
  if not exists (select 1 from public.finance_profiles where user_id = auth.uid() and active and role = 'owner') then
    raise exception 'Somente o responsável pode alterar acessos.';
  end if;
  if coalesce(p_can_view_card_loans,false) and not coalesce(p_can_view_values,false) and nullif(trim(coalesce(p_loan_borrower,'')),'') is null then
    raise exception 'Escolha a pessoa vinculada aos empréstimos no cartão.';
  end if;
  update public.finance_profiles
  set can_view_values = coalesce(p_can_view_values,false), can_view_card_loans = coalesce(p_can_view_card_loans,false), loan_borrower = trim(coalesce(p_loan_borrower,'')), active = coalesce(p_active,false), updated_at = now()
  where user_id = p_user_id and role = 'member';
  if not found then raise exception 'Usuário convidado não encontrado.'; end if;
end;
$$;

create or replace function public.finance_admin_cancel_invite(p_email text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
begin
  if not exists (select 1 from public.finance_profiles where user_id = auth.uid() and active and role = 'owner') then
    raise exception 'Somente o responsável pode cancelar convites.';
  end if;
  delete from public.finance_invites where email = lower(trim(p_email)) and consumed_at is null and role = 'member';
end;
$$;

revoke all on function public.finance_redact_values(jsonb) from public, anon, authenticated;
revoke all on function public.finance_normalize_category(text) from public, anon, authenticated;
revoke all on function public.finance_handle_new_user() from public, anon, authenticated;
revoke all on function public.finance_my_profile() from public, anon, authenticated;
revoke all on function public.finance_get_state() from public, anon, authenticated;
revoke all on function public.finance_save_state(jsonb,timestamptz) from public, anon, authenticated;
revoke all on function public.finance_admin_list_members() from public, anon, authenticated;
revoke all on function public.finance_admin_create_invite(text,text,boolean,boolean,text) from public, anon, authenticated;
revoke all on function public.finance_admin_update_member(uuid,boolean,boolean,text,boolean) from public, anon, authenticated;
revoke all on function public.finance_admin_cancel_invite(text) from public, anon, authenticated;

grant execute on function public.finance_my_profile() to authenticated;
grant execute on function public.finance_get_state() to authenticated;
grant execute on function public.finance_save_state(jsonb,timestamptz) to authenticated;
grant execute on function public.finance_admin_list_members() to authenticated;
grant execute on function public.finance_admin_create_invite(text,text,boolean,boolean,text) to authenticated;
grant execute on function public.finance_admin_update_member(uuid,boolean,boolean,text,boolean) to authenticated;
grant execute on function public.finance_admin_cancel_invite(text) to authenticated;

-- Bootstrap the owner by adding a row before Pablo signs up or accepts an invite.
-- Replace the address with Pablo's email and run this in the SQL Editor:
-- insert into public.finance_invites(email, display_name, role, can_view_values)
-- values (lower('EMAIL_DO_PABLO'), 'Pablo', 'owner', true)
-- on conflict (email) do update set display_name='Pablo', role='owner', can_view_values=true, consumed_at=null;
