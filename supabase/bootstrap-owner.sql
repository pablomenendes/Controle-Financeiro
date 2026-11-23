-- Execute no SQL Editor do Supabase depois de criar/confirmar o usuário Pablo em Authentication → Users.
-- Este script também vincula um usuário Pablo que já exista no Auth, sem depender do gatilho de novo cadastro.
insert into public.finance_invites(email, display_name, role, can_view_values)
values ('pablomenendes10@gmail.com', 'Pablo', 'owner', true)
on conflict (email) do update set
  display_name = 'Pablo',
  role = 'owner',
  can_view_values = true,
  invited_by = null,
  consumed_at = null;

insert into public.finance_profiles(user_id, email, display_name, role, can_view_values, active)
select id, lower(email), 'Pablo', 'owner', true, true
from auth.users
where lower(email) = 'pablomenendes10@gmail.com'
on conflict (user_id) do update set
  email = excluded.email,
  display_name = excluded.display_name,
  role = 'owner',
  can_view_values = true,
  active = true,
  updated_at = now();

update public.finance_invites
set consumed_at = now()
where email = 'pablomenendes10@gmail.com'
  and exists (select 1 from auth.users where lower(email) = 'pablomenendes10@gmail.com');
