// ============================================================
// CONFIGURAÇÃO CENTRAL DO SUPABASE - GABRIELLY MAKEUP
// ============================================================

// Substitua com a URL e anon Key do seu projeto Supabase:
const SUPABASE_CONFIG = {
    url: 'https://SUA_URL_SUPABASE_AQUI.supabase.co',
    anonKey: 'SUA_CHAVE_ANON_PUBLIC_AQUI'
};

// Inicialização do cliente Supabase
let supabaseClient = null;

function getSupabase() {
    if (!supabaseClient && window.supabase) {
        supabaseClient = window.supabase.createClient(SUPABASE_CONFIG.url, SUPABASE_CONFIG.anonKey);
    }
    return supabaseClient;
}
