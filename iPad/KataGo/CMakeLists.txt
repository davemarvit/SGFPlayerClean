cmake_minimum_required(VERSION 3.18)
project(QuietKataGo LANGUAGES C CXX)
set(CMAKE_CXX_STANDARD 14)
set(KATA "${CMAKE_CURRENT_SOURCE_DIR}/../.build/KataGo/cpp")
file(GLOB CORE "${KATA}/core/*.cpp")
list(FILTER CORE EXCLUDE REGEX "/(test|threadtest|mainargs)\\.cpp$")
file(GLOB GAME "${KATA}/game/*.cpp")
file(GLOB SEARCH "${KATA}/search/*.cpp")
add_library(QuietKataGo STATIC QuietKataGo.cpp ${CORE} ${GAME} ${SEARCH}
    ${KATA}/neuralnet/nninputs.cpp ${KATA}/neuralnet/sgfmetadata.cpp
    ${KATA}/neuralnet/modelversion.cpp ${KATA}/neuralnet/nneval.cpp
    ${KATA}/neuralnet/desc.cpp ${KATA}/neuralnet/eigenbackend.cpp
    ${KATA}/dataio/sgf.cpp ${KATA}/dataio/files.cpp ${KATA}/dataio/homedata.cpp
    ${KATA}/program/playutils.cpp)
target_compile_definitions(QuietKataGo PRIVATE USE_EIGEN_BACKEND)
target_compile_options(QuietKataGo PRIVATE -O3 -Wno-deprecated-declarations)
target_include_directories(QuietKataGo PRIVATE "${KATA}" "${KATA}/external" "${KATA}/external/filesystem-1.5.8/include" "${EIGEN_PATH}")
