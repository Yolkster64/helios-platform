cmake_minimum_required(VERSION 3.20)
project(helios_aihub_native LANGUAGES CXX VERSION 1.0.0)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
# Hide everything not explicitly exported, so the ABI surface is exactly the header.
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
set(CMAKE_VISIBILITY_INLINES_HIDDEN ON)

add_library(helios_aihub_native SHARED helios_aihub_native.cpp)
target_include_directories(helios_aihub_native PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

if(MSVC)
  # /O2 speed, /GL whole-program opt, /Qpar auto-parallelize the numeric loops.
  # Security: /GS stack cookies, /guard:cf Control Flow Guard, /CETCOMPAT shadow stack,
  # /DYNAMICBASE ASLR. These are cheap here and non-negotiable for shipped native code.
  target_compile_options(helios_aihub_native PRIVATE
    /W4 /permissive- /GS /guard:cf
    $<$<CONFIG:Release>:/O2 /GL /Qpar /fp:fast>)
  target_link_options(helios_aihub_native PRIVATE
    /guard:cf /DYNAMICBASE /NXCOMPAT /CETCOMPAT
    $<$<CONFIG:Release>:/LTCG>)
else()
  target_compile_options(helios_aihub_native PRIVATE
    -Wall -Wextra -Wpedantic
    -fstack-protector-strong -D_FORTIFY_SOURCE=2
    $<$<CONFIG:Release>:-O3 -ffast-math>)
  if(NOT APPLE)
    # ELF/GNU-ld hardening; Apple's linker rejects -z relro/now and would fail
    # the .dylib link.
    target_link_options(helios_aihub_native PRIVATE
      $<$<CONFIG:Release>:-Wl,-z,relro,-z,now>)
  endif()
endif()

# Sanitizer build for CI: catches the UB and overflow classes that the cpp-perf-reviewer
# agent looks for by hand. Enable with -DHELIOS_SANITIZE=ON.
option(HELIOS_SANITIZE "Build with address and undefined-behavior sanitizers" OFF)
if(HELIOS_SANITIZE AND NOT MSVC)
  target_compile_options(helios_aihub_native PRIVATE -fsanitize=address,undefined -g)
  target_link_options(helios_aihub_native PRIVATE -fsanitize=address,undefined)
endif()

install(TARGETS helios_aihub_native
        RUNTIME DESTINATION bin
        LIBRARY DESTINATION lib)
