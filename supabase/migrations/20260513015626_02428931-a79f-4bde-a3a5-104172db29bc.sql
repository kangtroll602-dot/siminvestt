
-- Ensure all roles can EXECUTE has_role used in RLS policies (storage included)
GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_admin(uuid) TO anon, authenticated, service_role;

-- Allow admins to upload to chat-attachments into any user's room folder
DROP POLICY IF EXISTS "Admins upload chat attachments" ON storage.objects;
CREATE POLICY "Admins upload chat attachments"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'chat-attachments' AND public.has_role(auth.uid(), 'admin'::public.app_role));

-- Public read access for chat-attachments (bucket is public, but be explicit)
DROP POLICY IF EXISTS "Public read chat attachments" ON storage.objects;
CREATE POLICY "Public read chat attachments"
ON storage.objects FOR SELECT TO anon, authenticated
USING (bucket_id = 'chat-attachments');
