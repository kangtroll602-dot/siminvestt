-- Ensure avatars bucket exists & is public
insert into storage.buckets (id, name, public) values ('avatars', 'avatars', true)
on conflict (id) do update set public = true;

-- Reset & recreate avatar storage policies (scoped to authenticated role)
do $$ begin
  begin drop policy "Users upload own avatar" on storage.objects; exception when undefined_object then null; end;
  begin drop policy "Users update own avatar" on storage.objects; exception when undefined_object then null; end;
  begin drop policy "Users delete own avatar" on storage.objects; exception when undefined_object then null; end;
  begin drop policy "Public read avatars" on storage.objects; exception when undefined_object then null; end;
end $$;

create policy "Public read avatars"
on storage.objects for select to anon, authenticated
using (bucket_id = 'avatars');

create policy "Users upload own avatar"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'avatars'
  and auth.uid() is not null
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "Users update own avatar"
on storage.objects for update to authenticated
using (
  bucket_id = 'avatars'
  and auth.uid() is not null
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "Users delete own avatar"
on storage.objects for delete to authenticated
using (
  bucket_id = 'avatars'
  and auth.uid() is not null
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- Admin chat moderation: allow admins to delete any chat message
do $$ begin
  begin drop policy "Admins delete chat messages" on public.chat_messages; exception when undefined_object then null; end;
end $$;

create policy "Admins delete chat messages"
on public.chat_messages for delete to authenticated
using (public.has_role(auth.uid(), 'admin'::public.app_role));
