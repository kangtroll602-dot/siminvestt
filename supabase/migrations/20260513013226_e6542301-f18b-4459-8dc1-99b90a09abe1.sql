-- Restore missing public triggers that are required by the app runtime.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE trigger_schema = 'public'
      AND event_object_table = 'profiles'
      AND trigger_name = 'profiles_touch_updated_at'
  ) THEN
    CREATE TRIGGER profiles_touch_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.touch_updated_at();
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE trigger_schema = 'public'
      AND event_object_table = 'deposits'
      AND trigger_name = 'deposits_touch_updated_at'
  ) THEN
    CREATE TRIGGER deposits_touch_updated_at
    BEFORE UPDATE ON public.deposits
    FOR EACH ROW
    EXECUTE FUNCTION public.touch_updated_at();
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE trigger_schema = 'public'
      AND event_object_table = 'withdraws'
      AND trigger_name = 'withdraws_touch_updated_at'
  ) THEN
    CREATE TRIGGER withdraws_touch_updated_at
    BEFORE UPDATE ON public.withdraws
    FOR EACH ROW
    EXECUTE FUNCTION public.touch_updated_at();
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE trigger_schema = 'public'
      AND event_object_table = 'news'
      AND trigger_name = 'news_touch_updated_at'
  ) THEN
    CREATE TRIGGER news_touch_updated_at
    BEFORE UPDATE ON public.news
    FOR EACH ROW
    EXECUTE FUNCTION public.touch_updated_at();
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE trigger_schema = 'public'
      AND event_object_table = 'site_settings'
      AND trigger_name = 'site_settings_touch_updated_at'
  ) THEN
    CREATE TRIGGER site_settings_touch_updated_at
    BEFORE UPDATE ON public.site_settings
    FOR EACH ROW
    EXECUTE FUNCTION public.touch_updated_at();
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE trigger_schema = 'public'
      AND event_object_table = 'profiles'
      AND trigger_name = 'profiles_guard_balance'
  ) THEN
    CREATE TRIGGER profiles_guard_balance
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.guard_profile_balance();
  END IF;
END $$;

-- Auth signup trigger: creates the user's profile and base role automatically.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'on_auth_user_created'
      AND tgrelid = 'auth.users'::regclass
  ) THEN
    CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();
  END IF;
END $$;

-- Keep these helper functions callable only through policies/triggers.
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.is_admin(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;