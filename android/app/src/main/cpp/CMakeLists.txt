cmake_minimum_required(VERSION 3.22.1)

project(ai_chat_ffi)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ============================================================================
# Fetch llama.cpp
# ============================================================================

include(FetchContent)

set(LLAMACPP_VERSION "master")
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../VERSIONS")
    file(READ "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../VERSIONS" VERSIONS_CONTENT)
    string(REGEX MATCH "LLAMA CPP_VERSION=([^\n]+)" _ "${VERSIONS_CONTENT}")
    if(CMAKE_MATCH_1)
        set(LLAMACPP_VERSION "${CMAKE_MATCH_1}")
    endif()
endif()

message(STATUS "Using llama.cpp version: ${LLAMACPP_VERSION}")

FetchContent_Declare(
    llamacpp
    GIT_REPOSITORY https://github.com/ggerganov/llama.cpp.git
    GIT_TAG        ${LLAMACPP_VERSION}
    GIT_SHALLOW    TRUE
    GIT_PROGRESS   TRUE
)

# Configure llama.cpp build
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON ON CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

# Disable unnecessary features
set(LLAMA_CURL OFF CACHE BOOL "" FORCE)
set(LLAMA_METAL OFF CACHE BOOL "" FORCE)
set(LLAMA_CUDA OFF CACHE BOOL "" FORCE)
set(LLAMA_VULKAN OFF CACHE BOOL "" FORCE)
set(LLAMA_KOMPUTE OFF CACHE BOOL "" FORCE)
set(LLAMA_SYCL OFF CACHE BOOL "" FORCE)
set(LLAMA_RPC OFF CACHE BOOL "" FORCE)

# Android-specific settings
if(ANDROID)
    set(LLAMA_OPENSSL OFF CACHE BOOL "" FORCE)
    set(GGML_LLAMAFILE OFF CACHE BOOL "" FORCE)
    
    # Enable NEON for ARM
    if(${ANDROID_ABI} MATCHES "^armeabi-v7a")
        set(GGML_NEON ON CACHE BOOL "" FORCE)
    elseif(${ANDROID_ABI} MATCHES "^arm64-v8a")
        set(GGML_NEON ON CACHE BOOL "" FORCE)
    endif()
endif()

FetchContent_MakeAvailable(llamacpp)

# ============================================================================
# Build ai_chat shared library for FFI
# ============================================================================

add_library(ai_chat SHARED
    ai_chat.cpp
)

target_include_directories(ai_chat PRIVATE
    ${llamacpp_SOURCE_DIR}/include
    ${llamacpp_SOURCE_DIR}/common
    ${llamacpp_SOURCE_DIR}/ggml/include
)

target_link_libraries(ai_chat PRIVATE
    llama
    common
    log
)

# Export FFI symbols
set_target_properties(ai_chat PROPERTIES
    C_VISIBILITY_PRESET hidden
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN YES
)

# 16KB page alignment for Android 15+ (API 35) compliance
if(ANDROID)
    target_link_options(ai_chat PRIVATE -Wl,-z,max-page-size=16384)
endif()

# Optimize for release builds
target_compile_options(ai_chat PRIVATE
    $<$<CONFIG:Release>:-O3 -ffast-math>
    $<$<CONFIG:Debug>:-O0 -g>
)

message(STATUS "FFI Binary: libai_chat.so will be built for ${ANDROID_ABI}")
message(STATUS "llama.cpp source: ${llamacpp_SOURCE_DIR}")
