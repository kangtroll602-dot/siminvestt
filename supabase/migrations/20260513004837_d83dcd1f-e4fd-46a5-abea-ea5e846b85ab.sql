-- =========================================================
-- ENUMS
-- =========================================================
create type public.app_role as enum ('admin', 'moderator', 'user');
create type public.tx_status as enum ('pending', 'approved', 'rejected');
create type public.sender_role as enum ('user', 'admin');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique,
  full_name text,
  phone text,
  avatar_url text,
  balance_idr numeric(18,2) not null default 0,
  is_blocked boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
create index idx_profiles_username on public.profiles(username);

create table public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  role app_role not null,
  created_at timestamptz not null default now(),
  unique (user_id, role)
);
alter table public.user_roles enable row level security;

create or replace function public.has_role(_user_id uuid, _role app_role)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.user_roles where user_id = _user_id and role = _role)
$$;

create or replace function public.is_admin(_user_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.has_role(_user_id, 'admin'::app_role)
$$;

create table public.deposits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  method text not null,
  sender_name text not null,
  amount_idr numeric(18,2) not null check (amount_idr >= 10000),
  proof_url text,
  status tx_status not null default 'pending',
  admin_note text,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.deposits enable row level security;
create index idx_deposits_user on public.deposits(user_id);
create index idx_deposits_status on public.deposits(status);

create table public.withdraws (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  bank_name text not null,
  account_holder text not null,
  account_number text not null,
  amount_idr numeric(18,2) not null check (amount_idr >= 50000),
  status tx_status not null default 'pending',
  admin_note text,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.withdraws enable row level security;
create index idx_withdraws_user on public.withdraws(user_id);
create index idx_withdraws_status on public.withdraws(status);

create table public.withdraw_locks (
  user_id uuid primary key references auth.users(id) on delete cascade,
  reason text,
  locked_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
alter table public.withdraw_locks enable row level security;

create table public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  room_user_id uuid not null references auth.users(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  sender_role sender_role not null,
  body text,
  attachment_url text,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.chat_messages enable row level security;
create index idx_chat_room on public.chat_messages(room_user_id, created_at);

create table public.news (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  excerpt text,
  content text not null,
  cover_url text,
  tag text,
  is_published boolean not null default true,
  author_id uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.news enable row level security;

create table public.site_settings (
  id boolean primary key default true check (id = true),
  site_name text not null default 'SimInvest',
  maintenance_mode boolean not null default false,
  telegram_chat_id text,
  logo_url text,
  favicon_url text,
  telegram_bot_token text,
  updated_at timestamptz not null default now()
);
alter table public.site_settings enable row level security;
insert into public.site_settings (id) values (true);

create table public.activity_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  action text not null,
  details jsonb,
  ip_address text,
  user_agent text,
  created_at timestamptz not null default now()
);
alter table public.activity_logs enable row level security;
create index idx_activity_logs_user on public.activity_logs(user_id);
create index idx_activity_logs_created on public.activity_logs(created_at desc);

-- USER LINKED BANK ACCOUNTS
create table public.user_bank_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  label text,
  bank_name text not null,
  account_holder text not null,
  account_number text not null,
  is_primary boolean not null default false,
  created_at timestamptz not null default now()
);
create index user_bank_accounts_user_id_idx on public.user_bank_accounts(user_id);
alter table public.user_bank_accounts enable row level security;

-- TIMESTAMP TRIGGERS
create or replace function public.touch_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin new.updated_at = now(); return new; end; $$;

create trigger trg_profiles_updated before update on public.profiles for each row execute function public.touch_updated_at();
create trigger trg_deposits_updated before update on public.deposits for each row execute function public.touch_updated_at();
create trigger trg_withdraws_updated before update on public.withdraws for each row execute function public.touch_updated_at();
create trigger trg_news_updated before update on public.news for each row execute function public.touch_updated_at();
create trigger trg_settings_updated before update on public.site_settings for each row execute function public.touch_updated_at();

-- AUTO-CREATE PROFILE + ROLE; first user becomes admin
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_role app_role := 'user'; v_count int;
begin
  insert into public.profiles (id, username, full_name, phone)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1)),
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', ''),
    coalesce(new.raw_user_meta_data->>'phone', '')
  ) on conflict (id) do nothing;
  select count(*) into v_count from public.user_roles where role = 'admin';
  if v_count = 0 then v_role := 'admin'; end if;
  insert into public.user_roles (user_id, role) values (new.id, v_role) on conflict do nothing;
  return new;
end; $$;

create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- Guard profile balance/is_blocked
create or replace function public.guard_profile_balance()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.has_role(auth.uid(), 'admin') then
    if new.balance_idr is distinct from old.balance_idr then new.balance_idr := old.balance_idr; end if;
    if new.is_blocked is distinct from old.is_blocked then new.is_blocked := old.is_blocked; end if;
  end if;
  return new;
end; $$;
create trigger trg_profile_balance_guard before update on public.profiles for each row execute function public.guard_profile_balance();

-- RLS POLICIES
create policy "Users view own profile" on public.profiles for select using (auth.uid() = id);
create policy "Admins view all profiles" on public.profiles for select using (public.has_role(auth.uid(), 'admin'));
create policy "Users update own basic profile" on public.profiles for update using (auth.uid() = id) with check (auth.uid() = id);
create policy "Admins update any profile" on public.profiles for update using (public.has_role(auth.uid(), 'admin'));

create policy "Users view own roles" on public.user_roles for select using (auth.uid() = user_id);
create policy "Admins view all roles" on public.user_roles for select using (public.has_role(auth.uid(), 'admin'));
create policy "Admins manage roles" on public.user_roles for all using (public.has_role(auth.uid(), 'admin')) with check (public.has_role(auth.uid(), 'admin'));

create policy "Users view own deposits" on public.deposits for select using (auth.uid() = user_id);
create policy "Users create own deposits" on public.deposits for insert with check (auth.uid() = user_id and status = 'pending');
create policy "Admins view all deposits" on public.deposits for select using (public.has_role(auth.uid(), 'admin'));
create policy "Admins update deposits" on public.deposits for update using (public.has_role(auth.uid(), 'admin'));

create policy "Users view own withdraws" on public.withdraws for select using (auth.uid() = user_id);
create policy "Users create own withdraws" on public.withdraws for insert with check (
  auth.uid() = user_id and status = 'pending'
  and not exists (select 1 from public.withdraw_locks where user_id = auth.uid())
);
create policy "Admins view all withdraws" on public.withdraws for select using (public.has_role(auth.uid(), 'admin'));
create policy "Admins update withdraws" on public.withdraws for update using (public.has_role(auth.uid(), 'admin'));

create policy "Users see own lock" on public.withdraw_locks for select using (auth.uid() = user_id);
create policy "Admins read locks" on public.withdraw_locks for select using (public.has_role(auth.uid(), 'admin'));
create policy "Admins manage locks" on public.withdraw_locks for all using (public.has_role(auth.uid(), 'admin')) with check (public.has_role(auth.uid(), 'admin'));

create policy "Users see own room messages" on public.chat_messages for select using (auth.uid() = room_user_id);
create policy "Users send in own room" on public.chat_messages for insert with check (auth.uid() = room_user_id and sender_id = auth.uid() and sender_role = 'user');
create policy "Admins see all chat" on public.chat_messages for select using (public.has_role(auth.uid(), 'admin'));
create policy "Admins send to any room" on public.chat_messages for insert with check (public.has_role(auth.uid(), 'admin') and sender_id = auth.uid() and sender_role = 'admin');
create policy "Admins delete chat" on public.chat_messages for delete using (public.has_role(auth.uid(), 'admin'));
create policy "Users mark read in own room" on public.chat_messages for update using (auth.uid() = room_user_id) with check (auth.uid() = room_user_id);
create policy "Admins update chat" on public.chat_messages for update using (public.has_role(auth.uid(), 'admin'));

create policy "Anyone reads published news" on public.news for select using (is_published = true);
create policy "Admins read all news" on public.news for select using (public.has_role(auth.uid(), 'admin'));
create policy "Admins manage news" on public.news for all using (public.has_role(auth.uid(), 'admin')) with check (public.has_role(auth.uid(), 'admin'));

create policy "Anyone reads site settings" on public.site_settings for select using (true);
create policy "Admins update settings" on public.site_settings for update using (public.has_role(auth.uid(), 'admin')) with check (public.has_role(auth.uid(), 'admin'));

create policy "Users view own logs" on public.activity_logs for select using (auth.uid() = user_id);
create policy "Authenticated insert logs" on public.activity_logs for insert with check (auth.uid() = user_id);
create policy "Admins read all logs" on public.activity_logs for select using (public.has_role(auth.uid(), 'admin'));

create policy "own bank accounts select" on public.user_bank_accounts for select using (auth.uid() = user_id);
create policy "own bank accounts insert" on public.user_bank_accounts for insert with check (auth.uid() = user_id);
create policy "own bank accounts update" on public.user_bank_accounts for update using (auth.uid() = user_id);
create policy "own bank accounts delete" on public.user_bank_accounts for delete using (auth.uid() = user_id);

-- REALTIME
alter table public.chat_messages replica identity full;
alter table public.deposits replica identity full;
alter table public.withdraws replica identity full;
alter table public.withdraw_locks replica identity full;
alter table public.profiles replica identity full;
alter table public.site_settings replica identity full;
alter table public.user_roles replica identity full;
alter table public.user_bank_accounts replica identity full;
do $$ begin
  begin alter publication supabase_realtime add table public.chat_messages; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.deposits; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.withdraws; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.withdraw_locks; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.profiles; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.site_settings; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.user_roles; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.user_bank_accounts; exception when duplicate_object then null; end;
end $$;

-- STORAGE BUCKETS
insert into storage.buckets (id, name, public) values ('avatars', 'avatars', true) on conflict (id) do update set public = true;
insert into storage.buckets (id, name, public) values ('chat-attachments', 'chat-attachments', true) on conflict (id) do update set public = true;
insert into storage.buckets (id, name, public) values ('site-assets', 'site-assets', true) on conflict (id) do nothing;

do $$ begin
  begin create policy "Anyone read avatars" on storage.objects for select using (bucket_id = 'avatars'); exception when duplicate_object then null; end;
  begin create policy "Users upload own avatar" on storage.objects for insert with check (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]); exception when duplicate_object then null; end;
  begin create policy "Users update own avatar" on storage.objects for update using (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]); exception when duplicate_object then null; end;
  begin create policy "Users delete own avatar" on storage.objects for delete using (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]); exception when duplicate_object then null; end;
  begin create policy "Anyone read chat attachments" on storage.objects for select using (bucket_id = 'chat-attachments'); exception when duplicate_object then null; end;
  begin create policy "Users upload chat attachments" on storage.objects for insert with check (bucket_id = 'chat-attachments' and auth.uid()::text = (storage.foldername(name))[1]); exception when duplicate_object then null; end;
  begin create policy "Anyone read site assets" on storage.objects for select using (bucket_id = 'site-assets'); exception when duplicate_object then null; end;
  begin create policy "Admins manage site assets" on storage.objects for all using (bucket_id = 'site-assets' and public.has_role(auth.uid(), 'admin')) with check (bucket_id = 'site-assets' and public.has_role(auth.uid(), 'admin')); exception when duplicate_object then null; end;
end $$;

revoke execute on function public.has_role(uuid, app_role) from anon, public;
revoke execute on function public.is_admin(uuid) from anon, public;
revoke execute on function public.handle_new_user() from anon, public, authenticated;
revoke execute on function public.guard_profile_balance() from anon, public, authenticated;
revoke execute on function public.touch_updated_at() from anon, public, authenticated;