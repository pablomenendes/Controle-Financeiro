-- Return invoice due and original statement dates in the restricted card-loan view.
create or replace function public.finance_get_state()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  member public.finance_profiles%rowtype;
  payload jsonb;
  state_updated_at timestamptz;
  visible_loans jsonb;
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

    payload := jsonb_build_object(
      'transactions', coalesce(visible_loans,'[]'::jsonb), 'settings','{}'::jsonb,
      'rules','[]'::jsonb, 'budgets','[]'::jsonb, 'accounts','[]'::jsonb,
      'recurrences','[]'::jsonb, 'goals','[]'::jsonb, 'importBatches','[]'::jsonb
    );
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

revoke all on function public.finance_get_state() from public, anon, authenticated;
grant execute on function public.finance_get_state() to authenticated;
