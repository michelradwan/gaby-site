// ============================================================
// CONFIGURAÇÃO CENTRAL DO SUPABASE - GABRIELLY MAKEUP
// ============================================================

const SUPABASE_CONFIG = {
    url: 'https://kttlfjdonkverkixaayx.supabase.co',
    anonKey: 'sb_publishable_gMw6EA-NsNFcnYd5qU8rkw_jroRy83d'
};

// Inicialização do cliente Supabase
let supabaseClient = null;

function getSupabase() {
    if (!supabaseClient && window.supabase) {
        supabaseClient = window.supabase.createClient(SUPABASE_CONFIG.url, SUPABASE_CONFIG.anonKey);
    }
    return supabaseClient;
}
