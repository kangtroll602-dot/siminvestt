create or replace function public.is_not_blocked(_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select not p.is_blocked from public.profiles p where p.id = _user_id), false)
$$;

grant execute on function public.is_not_blocked(uuid) to anon, authenticated, service_role;

create or replace function public.guard_profile_balance()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if not public.has_role(auth.uid(), 'admin'::app_role) then
    if new.balance_idr is distinct from old.balance_idr then
      new.balance_idr := old.balance_idr;
    end if;
    if new.is_blocked is distinct from old.is_blocked then
      new.is_blocked := old.is_blocked;
    end if;
  end if;
  return new;
end;
$function$;

revoke all on function public.guard_profile_balance() from public;

drop trigger if exists trg_profile_balance_guard on public.profiles;
create trigger trg_profile_balance_guard
before update on public.profiles
for each row
execute function public.guard_profile_balance();

alter table public.profiles enable row level security;
alter table public.deposits enable row level security;
alter table public.withdraws enable row level security;
alter table public.chat_messages enable row level security;
alter table public.user_bank_accounts enable row level security;

drop policy if exists "Users update own basic profile" on public.profiles;
create policy "Users update own basic profile"
on public.profiles
for update
to authenticated
using (auth.uid() = id and public.is_not_blocked(auth.uid()))
with check (auth.uid() = id and public.is_not_blocked(auth.uid()));

drop policy if exists "Users create own deposits" on public.deposits;
create policy "Users create own deposits"
on public.deposits
for insert
to authenticated
with check (auth.uid() = user_id and status = 'pending'::tx_status and public.is_not_blocked(auth.uid()));

drop policy if exists "Users create own withdraws" on public.withdraws;
create policy "Users create own withdraws"
on public.withdraws
for insert
to authenticated
with check (
  auth.uid() = user_id
  and status = 'pending'::tx_status
  and public.is_not_blocked(auth.uid())
  and not exists (select 1 from public.withdraw_locks where withdraw_locks.user_id = auth.uid())
);

drop policy if exists "Users send in own room" on public.chat_messages;
create policy "Users send in own room"
on public.chat_messages
for insert
to authenticated
with check (auth.uid() = room_user_id and sender_id = auth.uid() and sender_role = 'user'::sender_role and public.is_not_blocked(auth.uid()));

drop policy if exists "Users mark read in own room" on public.chat_messages;
create policy "Users mark read in own room"
on public.chat_messages
for update
to authenticated
using (auth.uid() = room_user_id and public.is_not_blocked(auth.uid()))
with check (auth.uid() = room_user_id and public.is_not_blocked(auth.uid()));

drop policy if exists "own bank accounts insert" on public.user_bank_accounts;
create policy "own bank accounts insert"
on public.user_bank_accounts
for insert
to authenticated
with check (auth.uid() = user_id and public.is_not_blocked(auth.uid()));

drop policy if exists "own bank accounts update" on public.user_bank_accounts;
create policy "own bank accounts update"
on public.user_bank_accounts
for update
to authenticated
using (auth.uid() = user_id and public.is_not_blocked(auth.uid()))
with check (auth.uid() = user_id and public.is_not_blocked(auth.uid()));

drop policy if exists "own bank accounts delete" on public.user_bank_accounts;
create policy "own bank accounts delete"
on public.user_bank_accounts
for delete
to authenticated
using (auth.uid() = user_id and public.is_not_blocked(auth.uid()));