cmake_minimum_required(VERSION 3.15.1)
project(cmake-spm-test LANGUAGES Swift)
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake/modules")

set(CMAKE_Swift_LANGUAGE_VERSION 5)

include(SwiftPM)

# Add SPM packages to test
add_spm(SwiftSVG 
  URL https://github.com/gr-markin/SwiftSVG
  BRANCH master
)