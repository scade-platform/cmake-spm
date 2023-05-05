function(add_spm name)
    set(options)
    set(one_args)
    set(multi_args URL BRANCH COMMIT VERSION)
    cmake_parse_arguments(ADD_SPM "${options}" "${one_args}" "${multi_args}" ${ARGN})

    execute_process(COMMAND swift build -c release
                    WORKING_DIRECTORY ${CMAKE_CURRENT_FUNCTION_LIST_DIR}/../..)

    get_property(targets GLOBAL PROPERTY ADD_SPM_ALL_TARGETS)
    list(APPEND targets "${name}")
    set_property(GLOBAL PROPERTY ADD_SPM_ALL_TARGETS "${targets}")

    message(STATUS "ALL TARGETS: ${targets}")

    #file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/spm-generated-${name}.cmake" "add_library(${name} ${name}.cpp)")
    #include("${CMAKE_CURRENT_BINARY_DIR}/spm-generated-${name}.cmake")
endfunction()