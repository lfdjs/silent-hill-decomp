cmake_minimum_required(VERSION 3.16)

project(
    silent_hill_portable
    VERSION 0.6.0
    LANGUAGES C)

include(CTest)

option(
    SH_ENABLE_WERROR
    "Treat warnings as errors in portable targets."
    ON)

option(
    SH_ENABLE_SANITIZERS
    "Enable AddressSanitizer and UndefinedBehaviorSanitizer."
    OFF)

set(SH_PUBLIC_INCLUDE_DIR "${CMAKE_CURRENT_LIST_DIR}/../include")
set(SH_TEST_DIR "${CMAKE_CURRENT_LIST_DIR}/../tests/portable")

function(sh_configure_target target)
    target_compile_features("${target}" PRIVATE c_std_11)

    if(MSVC)
        target_compile_options("${target}" PRIVATE /W4)

        if(SH_ENABLE_WERROR)
            target_compile_options("${target}" PRIVATE /WX)
        endif()
    elseif(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
        target_compile_options(
            "${target}"
            PRIVATE
                -Wall
                -Wextra
                -Wpedantic
                -Wconversion
                -Wshadow
                -Wstrict-prototypes)

        if(SH_ENABLE_WERROR)
            target_compile_options("${target}" PRIVATE -Werror)
        endif()

        if(SH_ENABLE_SANITIZERS)
            target_compile_options(
                "${target}"
                PRIVATE
                    -fsanitize=address,undefined
                    -fno-omit-frame-pointer)

            target_link_options(
                "${target}"
                PRIVATE
                    -fsanitize=address,undefined)
        endif()
    endif()
endfunction()

add_library(
    silent_hill_core_objects
    OBJECT
        src/sh_audio.c
        src/sh_clock.c
        src/sh_game.c
        src/sh_reference_game.c
        src/sh_input.c
        src/sh_io.c
        src/sh_memory.c
        src/sh_overlay.c
        src/sh_presentation.c
        src/sh_rng.c
        src/sh_runtime.c)

set_target_properties(
    silent_hill_core_objects
    PROPERTIES
        POSITION_INDEPENDENT_CODE ON
        C_VISIBILITY_PRESET hidden)

target_compile_definitions(
    silent_hill_core_objects
    PRIVATE
        SH_BUILDING_LIBRARY=1)

target_include_directories(
    silent_hill_core_objects
    PUBLIC
        "${SH_PUBLIC_INCLUDE_DIR}"
    PRIVATE
        "${CMAKE_CURRENT_LIST_DIR}/src")

sh_configure_target(silent_hill_core_objects)

add_library(
    silent_hill_core
    STATIC
        $<TARGET_OBJECTS:silent_hill_core_objects>)

target_include_directories(
    silent_hill_core
    PUBLIC
        "${SH_PUBLIC_INCLUDE_DIR}")

target_compile_definitions(
    silent_hill_core
    PUBLIC
        SH_STATIC=1)

set_target_properties(
    silent_hill_core
    PROPERTIES
        OUTPUT_NAME silent_hill_core)

add_library(
    silent_hill_core_shared
    SHARED
        $<TARGET_OBJECTS:silent_hill_core_objects>)

target_include_directories(
    silent_hill_core_shared
    PUBLIC
        "${SH_PUBLIC_INCLUDE_DIR}")

target_compile_definitions(
    silent_hill_core_shared
    PRIVATE
        SH_BUILDING_LIBRARY=1)

set_target_properties(
    silent_hill_core_shared
    PROPERTIES
        OUTPUT_NAME silent_hill_core
        VERSION "${PROJECT_VERSION}"
        SOVERSION "${PROJECT_VERSION_MAJOR}"
        C_VISIBILITY_PRESET hidden)

if(SH_ENABLE_SANITIZERS AND
   CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
    target_link_options(
        silent_hill_core_shared
        PRIVATE
            -fsanitize=address,undefined)
endif()

add_executable(
    silent-hill-headless
    "${CMAKE_CURRENT_LIST_DIR}/../tools/portable/sh_headless_runner.c")

target_link_libraries(
    silent-hill-headless
    PRIVATE
        silent_hill_core)

sh_configure_target(silent-hill-headless)

if(BUILD_TESTING)
    foreach(
        test_name
        IN ITEMS
            rng
            api_contract
            abi_layout
            timing
            input
            io
            memory
            overlay
            game
            reference_trace
            presentation_audio
            konami_trace)

        add_executable(
            "sh_${test_name}_tests"
            "${SH_TEST_DIR}/test_${test_name}.c")

        target_link_libraries(
            "sh_${test_name}_tests"
            PRIVATE
                silent_hill_core)

        sh_configure_target("sh_${test_name}_tests")

        add_test(
            NAME "sh_${test_name}_tests"
            COMMAND "sh_${test_name}_tests")
    endforeach()
endif()

# Stage 09: diagnostic PC host (not linked into the portable ABI library).
option(SH_BUILD_PC_RUNNER "Build the desktop diagnostic host." ON)
if(SH_BUILD_PC_RUNNER)
    add_library(sh_pc_app STATIC
        "${CMAKE_CURRENT_LIST_DIR}/../ports/pc/sh_pc_app.c")
    target_link_libraries(sh_pc_app PUBLIC silent_hill_core)
    target_include_directories(sh_pc_app PUBLIC
        "${CMAKE_CURRENT_LIST_DIR}/../ports/pc"
        "${SH_PUBLIC_INCLUDE_DIR}")
    sh_configure_target(sh_pc_app)

    add_library(sh_pc_tim STATIC
        "${CMAKE_CURRENT_LIST_DIR}/../ports/pc/sh_tim.c")
    target_include_directories(sh_pc_tim PUBLIC
        "${CMAKE_CURRENT_LIST_DIR}/../ports/pc")
    sh_configure_target(sh_pc_tim)

    add_executable(silent-hill-tim
        "${CMAKE_CURRENT_LIST_DIR}/../ports/pc/sh_tim_tool.c")
    target_link_libraries(silent-hill-tim PRIVATE sh_pc_tim)
    sh_configure_target(silent-hill-tim)

    add_executable(silent-hill-pc
        "${CMAKE_CURRENT_LIST_DIR}/../ports/pc/sh_pc_runner.c")
    target_link_libraries(silent-hill-pc PRIVATE sh_pc_app sh_pc_tim)
    sh_configure_target(silent-hill-pc)

    if(UNIX AND NOT APPLE)
        find_package(X11 QUIET)
        if(X11_FOUND)
            target_include_directories(silent-hill-pc PRIVATE ${X11_INCLUDE_DIR})
            target_link_libraries(silent-hill-pc PRIVATE ${X11_LIBRARIES})
            target_compile_definitions(silent-hill-pc PRIVATE SH_PC_HAVE_X11=1)
        endif()
    endif()

    if(BUILD_TESTING)
        add_executable(sh_tim_tests
            "${SH_TEST_DIR}/test_tim.c")
        target_link_libraries(sh_tim_tests PRIVATE sh_pc_tim)
        sh_configure_target(sh_tim_tests)
        add_test(NAME sh_tim_tests COMMAND sh_tim_tests)
        add_executable(sh_pc_host_tests
            "${SH_TEST_DIR}/test_pc_host.c")
        target_link_libraries(sh_pc_host_tests PRIVATE sh_pc_app)
        sh_configure_target(sh_pc_host_tests)
        add_test(NAME sh_pc_host_tests COMMAND sh_pc_host_tests)
        add_test(NAME sh_pc_cli_smoke
            COMMAND silent-hill-pc --headless --fast --max-ticks 300)
        set_tests_properties(sh_pc_cli_smoke PROPERTIES
            PASS_REGULAR_EXPRESSION "Reached unsupported state: KcetLogo")
    endif()
endif()

# Stage 10: platform-neutral example; no X11, SDL, GPU or SPU required.
option(SH_BUILD_PORT_TEMPLATE "Build the portable host integration template." ON)
if(SH_BUILD_PORT_TEMPLATE)
    add_library(sh_port_template STATIC
        "${CMAKE_CURRENT_LIST_DIR}/../ports/platform-template/sh_port_template.c")
    target_include_directories(sh_port_template PUBLIC
        "${CMAKE_CURRENT_LIST_DIR}/../ports/platform-template")
    target_link_libraries(sh_port_template PUBLIC silent_hill_core)
    sh_configure_target(sh_port_template)

    add_executable(silent-hill-port-template
        "${CMAKE_CURRENT_LIST_DIR}/../ports/platform-template/sh_port_template_main.c")
    target_link_libraries(silent-hill-port-template PRIVATE sh_port_template)
    sh_configure_target(silent-hill-port-template)

    if(BUILD_TESTING)
        add_executable(sh_port_template_tests
            "${SH_TEST_DIR}/test_port_template.c")
        target_link_libraries(sh_port_template_tests PRIVATE sh_port_template)
        sh_configure_target(sh_port_template_tests)
        add_test(NAME sh_port_template_tests COMMAND sh_port_template_tests)
        add_test(NAME sh_port_template_cli_smoke
            COMMAND silent-hill-port-template)
        set_tests_properties(sh_port_template_cli_smoke PROPERTIES
            PASS_REGULAR_EXPRESSION "state=KcetLogo")
    endif()
endif()
