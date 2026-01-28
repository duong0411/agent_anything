/**
 * @file native_platform_adapter.cpp
 * @brief Default Native Platform Adapter Implementation
 *
 * Provides standard C++ implementations for file I/O and time utils.
 * This allows FFI consumers (Flutter/Dart) to use the library without
 * implementing low-level file callbacks.
 */

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <fstream>
#include <sys/stat.h>

#include "rac/core/rac_platform_adapter.h"

// =============================================================================
// FILE SYSTEM IO
// =============================================================================

namespace {

rac_bool_t native_file_exists(const char* path, void* user_data) {
    if (!path) return RAC_FALSE;
    return std::filesystem::exists(path) ? RAC_TRUE : RAC_FALSE;
}

rac_result_t native_file_read(const char* path, void** out_data, size_t* out_size, void* user_data) {
    if (!path || !out_data || !out_size) return RAC_ERROR_INVALID_ARGUMENT;

    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file.is_open()) return RAC_ERROR_FILE_NOT_FOUND;

    std::streamsize size = file.tellg();
    if (size < 0) return RAC_ERROR_FILE_READ_FAILED;

    file.seekg(0, std::ios::beg);

    void* buffer = malloc(size);
    if (!buffer) return RAC_ERROR_OUT_OF_MEMORY;

    if (!file.read(static_cast<char*>(buffer), size)) {
        free(buffer);
        return RAC_ERROR_FILE_READ_FAILED;
    }

    *out_data = buffer;
    *out_size = static_cast<size_t>(size);
    return RAC_SUCCESS;
}

rac_result_t native_file_write(const char* path, const void* data, size_t size, void* user_data) {
    if (!path || !data) return RAC_ERROR_INVALID_ARGUMENT;

    std::ofstream file(path, std::ios::binary);
    if (!file.is_open()) return RAC_ERROR_FILE_WRITE_FAILED;

    if (!file.write(static_cast<const char*>(data), size)) {
        return RAC_ERROR_FILE_WRITE_FAILED;
    }

    return RAC_SUCCESS;
}

rac_result_t native_file_delete(const char* path, void* user_data) {
    if (!path) return RAC_ERROR_INVALID_ARGUMENT;
    std::filesystem::remove(path);
    return RAC_SUCCESS;
}

// =============================================================================
// TIME & LOGGING
// =============================================================================

int64_t native_now_ms(void* user_data) {
    auto now = std::chrono::system_clock::now();
    return std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()).count();
}

void native_log(rac_log_level_t level, const char* category, const char* message, void* user_data) {
    const char* level_str = "DEBUG";
    switch (level) {
        case RAC_LOG_ERROR: level_str = "ERROR"; break;
        case RAC_LOG_WARNING: level_str = "WARN "; break;
        case RAC_LOG_INFO: level_str = "INFO "; break;
        default: break;
    }
    fprintf(stderr, "[%s] [%s] %s\n", level_str, category ? category : "RAC", message ? message : "");
}

} // namespace

// =============================================================================
// PUBLIC FACTORY
// =============================================================================

/**
 * Helper to populate a platform adapter with native defaults.
 * Dart can call this to get a pre-filled struct, then override specific fields
 * (like secure_storage or http_download) if needed.
 */
extern "C" void rac_platform_adapter_init_native(rac_platform_adapter_t* adapter) {
    if (!adapter) return;
    
    memset(adapter, 0, sizeof(rac_platform_adapter_t));
    
    adapter->file_exists = native_file_exists;
    adapter->file_read = native_file_read;
    adapter->file_write = native_file_write;
    adapter->file_delete = native_file_delete;
    adapter->now_ms = native_now_ms;
    adapter->log = native_log;
    
    // HTTP and Secure Storage are left NULL 
    // (Caller/Dart should provide them if network/storage is needed)
}
