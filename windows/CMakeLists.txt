# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(echo LANGUAGES CXX)

set(BINARY_NAME "echo")
cmake_policy(VERSION 3.14...3.25)

# ---------------------------------------------------------------------------
# Force modern C++ everywhere (runner + plugins).
# C++17 is the safest baseline for Flutter Windows plugins.
# ---------------------------------------------------------------------------
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(MSVC)
    # Ensure /std flag is present even if a plugin target ignores CMAKE_CXX_STANDARD.
    add_compile_options(/std:c++17)
endif()

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
    set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release" CACHE STRING "" FORCE)
else()
    if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
        set(CMAKE_BUILD_TYPE "Debug" CACHE STRING "Flutter build mode" FORCE)
        set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS "Debug" "Profile" "Release")
    endif()
endif()

# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Standard settings applied to Flutter runner target(s) where appropriate.
function(APPLY_STANDARD_SETTINGS TARGET)
    target_compile_features(${TARGET} PUBLIC cxx_std_17)

    if(MSVC)
        target_compile_options(${TARGET} PRIVATE /W4 /WX /wd4100 /EHsc)
    else()
        target_compile_options(${TARGET} PRIVATE -Wall -Wextra -Werror)
    endif()

    # Many Flutter templates disable exceptions; keep consistent with template behavior.
    target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
    target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# Generated plugin build rules.
include(flutter/generated_plugins.cmake)

# ---------------------------------------------------------------------------
# Extra safety: pin any plugin targets to the same C++ standard if they exist.
# (Not all plugins create distinct CMake targets, but this helps when they do.)
# ---------------------------------------------------------------------------
foreach(_t
        flutter_secure_storage_windows_plugin
        nsd_windows_plugin
)
    if(TARGET ${_t})
        set_property(TARGET ${_t} PROPERTY CXX_STANDARD 17)
        set_property(TARGET ${_t} PROPERTY CXX_STANDARD_REQUIRED ON)
        set_property(TARGET ${_t} PROPERTY CXX_EXTENSIONS OFF)
        if(MSVC)
            target_compile_options(${_t} PRIVATE /std:c++17)
        endif()
    endif()
endforeach()

# === Installation ===
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)

if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
    set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME}
        RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
        COMPONENT Runtime
)

install(FILES "${FLUTTER_ICU_DATA_FILE}"
        DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
        COMPONENT Runtime
)

install(FILES "${FLUTTER_LIBRARY}"
        DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
        COMPONENT Runtime
)

if(PLUGIN_BUNDLED_LIBRARIES)
    install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
            DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
            COMPONENT Runtime
    )
endif()

set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
        DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
        COMPONENT Runtime
)

set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime
)

install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
        DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
        COMPONENT Runtime
)

install(FILES "${AOT_LIBRARY}"
        DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
        CONFIGURATIONS Profile;Release
        COMPONENT Runtime
)