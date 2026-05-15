-- Enable realtime for all tables
alter table public.profiles replica identity full;
alter table public.deposits replica identity full;
alter table public.withdraws replica identity full;
alter table public.withdraw_locks replica identity full;
alter table public.chat_messages replica identity full;
alter table public.news replica identity full;
alter table public.site_settings replica identity full;
alter table public.user_roles replica identity full;
alter table public.activity_logs replica identity full;
alter table public.user_bank_accounts replica identity full;

do $$
declare t text;
begin
  for t in select unnest(array['profiles','deposits','withdraws','withdraw_locks','chat_messages','news','site_settings','user_roles','activity_logs','user_bank_accounts'])
  loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;

-- Re-attach handle_new_user trigger to auth.users (lost on cloud reset)
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Re-attach guard trigger and updated_at triggers
drop trigger if exists trg_profile_balance_guard on public.profiles;
create trigger trg_profile_balance_guard
  before update on public.profiles
  for each row execute function public.guard_profile_balance();

drop trigger if exists trg_profiles_updated on public.profiles;
create trigger trg_profiles_updated before update on public.profiles
  for each row execute function public.touch_updated_at();

drop trigger if exists trg_deposits_updated on public.deposits;
create trigger trg_deposits_updated before update on public.deposits
  for each row execute function public.touch_updated_at();

drop trigger if exists trg_withdraws_updated on public.withdraws;
create trigger trg_withdraws_updated before update on public.withdraws
  for each row execute function public.touch_updated_at();

drop trigger if exists trg_news_updated on public.news;
create trigger trg_news_updated before update on public.news
  for each row execute function public.touch_updated_at();

drop trigger if exists trg_settings_updated on public.site_settings;
create trigger trg_settings_updated before update on public.site_settings
  for each row execute function public.touch_updated_at();

-- Ensure single settings row exists
insert into public.site_settings (id) values (true) on conflict (id) do nothing;