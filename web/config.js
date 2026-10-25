// Supabase project for accounts and sync, shared with the iOS app. The publishable (anon) key is meant to be
// public: every table is protected by row-level security, so it only gives access to the signed-in learner's rows.
// Set both to "" to run the web version offline only.
export const SUPABASE_URL = "https://ujhmmngxqowgtteowbdg.supabase.co";
export const SUPABASE_ANON_KEY = "sb_publishable_Im99OT1stuP8Fca7X-zSQA_rmjADfGi";
