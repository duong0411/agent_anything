#include <android/log.h>
#include <cmath>
#include <cstdlib>
#include <sstream>
#include <string>
#include <unistd.h>
#include <vector>

#include "llama.h"
#include "common.h"

#define TAG "AIChatFFI"
#define LOGi(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGe(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)
#define LOGw(...) __android_log_print(ANDROID_LOG_WARN, TAG, __VA_ARGS__)
#define LOGd(...) __android_log_print(ANDROID_LOG_DEBUG, TAG, __VA_ARGS__)
#define LOGv(...) __android_log_print(ANDROID_LOG_VERBOSE, TAG, __VA_ARGS__)

// Configuration constants
constexpr int N_THREADS_MIN = 2;
constexpr int N_THREADS_MAX = 4;
constexpr int N_THREADS_HEADROOM = 2;
constexpr int DEFAULT_CONTEXT_SIZE = 256;
constexpr int OVERFLOW_HEADROOM = 4;
constexpr int BATCH_SIZE = 1;
constexpr float DEFAULT_SAMPLER_TEMP = 0.7f;

// Global state
static llama_model* g_model = nullptr;
static llama_context* g_context = nullptr;
static llama_batch g_batch;
static llama_sampler* g_sampler = nullptr;

static std::vector<llama_chat_message> chat_msgs;
static llama_pos system_prompt_position = 0;
static llama_pos current_position = 0;
static llama_pos stop_generation_position = 0;
static std::string cached_token_chars;
static std::ostringstream assistant_ss;

// Helper functions
static void reset_long_term_states(const bool clear_kv_cache = true) {
    chat_msgs.clear();
    system_prompt_position = 0;
    current_position = 0;
    
    if (clear_kv_cache && g_context) {
        llama_memory_clear(llama_get_memory(g_context), false);
    }
}

static void reset_short_term_states() {
    stop_generation_position = 0;
    cached_token_chars.clear();
    assistant_ss.str("");
}

static void shift_context() {
    const int n_discard = (current_position - system_prompt_position) / 2;
    LOGi("Discarding %d tokens", n_discard);
    llama_memory_seq_rm(llama_get_memory(g_context), 0, system_prompt_position, 
                       system_prompt_position + n_discard);
    llama_memory_seq_add(llama_get_memory(g_context), 0, 
                        system_prompt_position + n_discard, current_position, -n_discard);
    current_position -= n_discard;
    LOGi("Context shifting done! Current position: %d", current_position);
}

static int decode_tokens_in_batches(llama_context* context, llama_batch& batch,
                                    const std::vector<llama_token>& tokens,
                                    const llama_pos start_pos,
                                    const bool compute_last_logit = false) {
    LOGd("Decode %d tokens starting at position %d", (int)tokens.size(), start_pos);
    
    for (int i = 0; i < (int)tokens.size(); i += BATCH_SIZE) {
        const int cur_batch_size = std::min((int)tokens.size() - i, BATCH_SIZE);
        common_batch_clear(batch);
        
        if (start_pos + i + cur_batch_size >= DEFAULT_CONTEXT_SIZE - OVERFLOW_HEADROOM) {
            LOGw("Current batch won't fit into context! Shifting...");
            shift_context();
        }
        
        for (int j = 0; j < cur_batch_size; j++) {
            const llama_token token_id = tokens[i + j];
            const llama_pos position = start_pos + i + j;
            const bool want_logit = compute_last_logit && (i + j == tokens.size() - 1);
            common_batch_add(batch, token_id, position, {0}, want_logit);
        }
        
        const int decode_result = llama_decode(context, batch);
        if (decode_result) {
            LOGe("llama_decode failed w/ %d", decode_result);
            return 1;
        }
    }
    return 0;
}

static bool is_valid_utf8(const char* string) {
    if (!string) return true;
    
    const auto* bytes = (const unsigned char*)string;
    int num;
    
    while (*bytes != 0x00) {
        if ((*bytes & 0x80) == 0x00) {
            num = 1;
        } else if ((*bytes & 0xE0) == 0xC0) {
            num = 2;
        } else if ((*bytes & 0xF0) == 0xE0) {
            num = 3;
        } else if ((*bytes & 0xF8) == 0xF0) {
            num = 4;
        } else {
            return false;
        }
        
        bytes += 1;
        for (int i = 1; i < num; ++i) {
            if ((*bytes & 0xC0) != 0x80) {
                return false;
            }
            bytes += 1;
        }
    }
    return true;
}

// ============================================================================
// FFI EXPORTS for Flutter
// ============================================================================

extern "C" {

__attribute__((visibility("default"))) __attribute__((used))
void init_ffi(const char* backend_path) {
    llama_log_set([](ggml_log_level level, const char* text, void* user_data) {
        __android_log_print(ANDROID_LOG_INFO, TAG, "%s", text);
    }, nullptr);
    
    if (backend_path && backend_path[0] != '\0') {
        LOGi("Loading backends from %s", backend_path);
        ggml_backend_load_all_from_path(backend_path);
    } else {
        LOGi("Loading system default backends - DISABLED for stability");
        // ggml_backend_load_all();
    }
    
    llama_backend_init();
    LOGi("Backend initiated; Log handler set.");
}

__attribute__((visibility("default"))) __attribute__((used))
int load_model_ffi(const char* model_path) {
    if (!model_path) {
        LOGe("Model path is null");
        return 1;
    }
    
    LOGd("Loading model from: %s", model_path);
    llama_model_params model_params = llama_model_default_params();
    g_model = llama_model_load_from_file(model_path, model_params);
    
    if (!g_model) {
        LOGe("Failed to load model");
        return 1;
    }
    
    LOGi("Model loaded successfully");
    return 0;
}

__attribute__((visibility("default"))) __attribute__((used))
int prepare_session_ffi() {
    if (!g_model) {
        LOGe("Model not loaded");
        return 1;
    }
    
    const int n_threads = std::max(N_THREADS_MIN, std::min(N_THREADS_MAX,
        (int)sysconf(_SC_NPROCESSORS_ONLN) - N_THREADS_HEADROOM));
    LOGi("Using %d threads", n_threads);
    
    llama_context_params ctx_params = llama_context_default_params();
    const int trained_context_size = llama_model_n_ctx_train(g_model);
    
    ctx_params.n_ctx = DEFAULT_CONTEXT_SIZE;
    ctx_params.n_batch = BATCH_SIZE;
    ctx_params.n_ubatch = BATCH_SIZE;
    ctx_params.n_threads = n_threads;
    ctx_params.n_threads_batch = n_threads;
    ctx_params.no_perf = true;
    
    g_context = llama_init_from_model(g_model, ctx_params);
    if (!g_context) {
        LOGe("Failed to create context");
        return 1;
    }
    
    g_batch = llama_batch_init(BATCH_SIZE, 0, 1);
    
    // Initialize sampler
    auto sparams = llama_sampler_chain_default_params();
    sparams.no_perf = true;
    g_sampler = llama_sampler_chain_init(sparams);
    
    llama_sampler_chain_add(g_sampler, llama_sampler_init_top_k(40));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_top_p(0.95f, 1));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_temp(DEFAULT_SAMPLER_TEMP));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));
    
    LOGi("Session prepared successfully");
    return 0;
}

__attribute__((visibility("default"))) __attribute__((used))
int process_system_prompt_ffi(const char* system_prompt) {
    if (!system_prompt || !g_context) {
        LOGe("Invalid parameters");
        return 1;
    }
    
    reset_long_term_states();
    reset_short_term_states();
    
    LOGd("System prompt received: %s", system_prompt);
    
    // Simple format: just use the system prompt as-is
    std::string formatted_prompt = std::string("System: ") + system_prompt + "\n";
    
    const auto system_tokens = common_tokenize(g_context, formatted_prompt, true, true);
    
    if ((int)system_tokens.size() > DEFAULT_CONTEXT_SIZE - OVERFLOW_HEADROOM) {
        LOGe("System prompt too long: %d tokens", (int)system_tokens.size());
        return 1;
    }
    
    if (decode_tokens_in_batches(g_context, g_batch, system_tokens, current_position)) {
        LOGe("Failed to decode system tokens");
        return 2;
    }
    
    system_prompt_position = current_position = (int)system_tokens.size();
    LOGi("System prompt processed successfully");
    return 0;
}

__attribute__((visibility("default"))) __attribute__((used))
int process_user_prompt_ffi(const char* user_prompt, int n_predict) {
    if (!user_prompt || !g_context) {
        LOGe("Invalid parameters");
        return 1;
    }
    
    reset_short_term_states();
    
    LOGd("User prompt received: %s", user_prompt);
    
    std::string formatted_prompt = std::string("User: ") + user_prompt + "\nAssistant: ";
    auto user_tokens = common_tokenize(g_context, formatted_prompt, true, true);
    
    const int user_prompt_size = (int)user_tokens.size();
    const int max_batch_size = DEFAULT_CONTEXT_SIZE - OVERFLOW_HEADROOM;
    
    if (user_prompt_size > max_batch_size) {
        const int skipped_tokens = user_prompt_size - max_batch_size;
        user_tokens.resize(max_batch_size);
        LOGw("User prompt too long! Skipped %d tokens", skipped_tokens);
    }
    
    if (decode_tokens_in_batches(g_context, g_batch, user_tokens, current_position, true)) {
        LOGe("Failed to decode user tokens");
        return 2;
    }
    
    current_position += user_prompt_size;
    stop_generation_position = current_position + n_predict;
    
    LOGi("User prompt processed successfully");
    return 0;
}

__attribute__((visibility("default"))) __attribute__((used))
const char* generate_next_token_ffi() {
    if (!g_context || !g_sampler) {
        LOGe("Context or sampler not initialized");
        return nullptr;
    }
    
    if (current_position >= DEFAULT_CONTEXT_SIZE - OVERFLOW_HEADROOM) {
        LOGw("Context full! Shifting...");
        shift_context();
    }
    
    if (current_position >= stop_generation_position) {
        LOGd("Reached stop position: %d", stop_generation_position);
        return nullptr;
    }
    
    const auto new_token_id = llama_sampler_sample(g_sampler, g_context, -1);
    llama_sampler_accept(g_sampler, new_token_id);
    
    common_batch_clear(g_batch);
    common_batch_add(g_batch, new_token_id, current_position, {0}, true);
    
    if (llama_decode(g_context, g_batch) != 0) {
        LOGe("llama_decode failed for generated token");
        return nullptr;
    }
    
    current_position++;
    
    const auto vocab = llama_model_get_vocab(g_model);
    if (llama_vocab_is_eog(vocab, new_token_id)) {
        LOGd("End of generation (EOG token)");
        return nullptr;
    }
    
    auto new_token_chars = common_token_to_piece(g_context, new_token_id);
    cached_token_chars += new_token_chars;
    
    static std::string ret_buf;
    ret_buf.clear();
    
    if (is_valid_utf8(cached_token_chars.c_str())) {
        ret_buf = cached_token_chars;
        assistant_ss << cached_token_chars;
        cached_token_chars.clear();
        return ret_buf.c_str();
    } else {
        return "";
    }
}

__attribute__((visibility("default"))) __attribute__((used))
void stop_generation_ffi() {
    reset_short_term_states();
    LOGi("Generation stopped");
}

__attribute__((visibility("default"))) __attribute__((used))
void reset_conversation_ffi() {
    reset_long_term_states();
    reset_short_term_states();
    LOGi("Conversation reset");
}

__attribute__((visibility("default"))) __attribute__((used))
void unload_ffi() {
    reset_long_term_states(false);
    reset_short_term_states();
    
    if (g_sampler) {
        llama_sampler_free(g_sampler);
        g_sampler = nullptr;
    }
    
    if (g_context) {
        llama_batch_free(g_batch);
        llama_free(g_context);
        g_context = nullptr;
    }
    
    if (g_model) {
        llama_model_free(g_model);
        g_model = nullptr;
    }
    
    LOGi("Resources unloaded");
}

__attribute__((visibility("default"))) __attribute__((used))
void shutdown_ffi() {
    unload_ffi();
    llama_backend_free();
    LOGi("Backend shutdown");
}

__attribute__((visibility("default"))) __attribute__((used))
const char* get_system_info_ffi() {
    return llama_print_system_info();
}

} // extern "C"
