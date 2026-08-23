const SUPABASE_URL = "https://yoycjztzdqirdrogrkat.supabase.co";

const SUPABASE_ANON_KEY = "sb_publishable_-ToK1fQ1ach7nEpopLHCdg_yN_Uu7uq";

window.supabaseClient = window.supabase.createClient(
  SUPABASE_URL,
  SUPABASE_ANON_KEY
);