revoke execute on function public.has_role(uuid, app_role) from authenticated;
revoke execute on function public.is_admin(uuid) from authenticated;

-- Replace broad public-listing select policies with object-level "anyone with URL can read"
-- by removing the SELECT policy (Supabase public buckets still allow direct getPublicUrl access).
do $$ begin
  begin drop policy "Anyone read avatars" on storage.objects; exception when undefined_object then null; end;
  begin drop policy "Anyone read chat attachments" on storage.objects; exception when undefined_object then null; end;
  begin drop policy "Anyone read site assets" on storage.objects; exception when undefined_object then null; end;
end $$;