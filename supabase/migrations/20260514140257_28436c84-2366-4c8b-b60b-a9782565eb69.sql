drop policy if exists "Users update own basic profile" on public.profiles;
create policy "Users update own basic profile"
on public.profiles
for update
to authenticated
using (auth.uid() = id and is_blocked = false)
with check (auth.uid() = id and is_blocked = false);

drop policy if exists "Users create own deposits" on public.deposits;
create policy "Users create own deposits"
on public.deposits
for insert
to authenticated
with check (
  auth.uid() = user_id
  and status = 'pending'::tx_status
  and exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_blocked = false)
);

drop policy if exists "Users create own withdraws" on public.withdraws;
create policy "Users create own withdraws"
on public.withdraws
for insert
to authenticated
with check (
  auth.uid() = user_id
  and status = 'pending'::tx_status
  and exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_blocked = false)
  and not exists (select 1 from public.withdraw_locks where withdraw_locks.user_id = auth.uid())
);

drop policy if exists "Users send in own room" on public.chat_messages;
create policy "Users send in own room"
on public.chat_messages
for insert
to authenticated
with check (
  auth.uid() = room_user_id
  and sender_id = auth.uid()
  and sender_role = 'user'::sender_role
  and exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_blocked = false)
);

drop policy if exists "Users mark read in own room" on public.chat_messages;
create policy "Users mark read in own room"
on public.chat_messages
for update
to authenticated
using (
  auth.uid() = room_user_id
  and exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_blocked = false)
)
with check (
  auth.uid() = room_user_id
  and exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_blocked = false)
);

drop policy if exists "own bank accounts insert" on public.user_bank_accounts;
create policy "own bank accounts insert"
on public.user_bank_accounts
for insert
to authenticated
with check (
  auth.uid() = user_id
  and exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_blocked = false)
);

drop policy if exists "own bank accounts update" on public.user_bank_accounts;
create policy "own bank accounts update"
on public.user_bank_accounts
for update
to authenticated
using (
  auth.uid() = user_id
  and exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_blocked = false)
)
with check (
  auth.uid() = user_id
  and exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_blocked = false)
);

drop policy if exists "own bank accounts delete" on public.user_bank_accounts;
create policy "own bank accounts delete"
on public.user_bank_accounts
for delete
to authenticated
using (
  auth.uid() = user_id
  and exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_blocked = false)
);

revoke all on function public.is_not_blocked(uuid) from public, anon, authenticated;
drop function if exists public.is_not_blocked(uuid);