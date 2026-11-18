-- Run this once in Supabase SQL Editor after schema.sql and before Pablo signs up.
insert into public.finance_invites(email, display_name, role, can_view_values)
values (lower('EMAIL_DO_PABLO'), 'Pablo', 'owner', true)
on conflict (email) do update set
  display_name = 'Pablo',
  role = 'owner',
  can_view_values = true,
  consumed_at = null;
