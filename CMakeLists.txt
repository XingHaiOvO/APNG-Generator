cmake_minimum_required(VERSION 3.16)
project(ApngGenerator)

# 禁用 Qt 的 OpenGL 依赖，避免 macOS 链接 AGL
if(APPLE)
    add_definitions(-DQT_NO_OPENGL -DQT_NO_OPENGL_ES)
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(QT NAMES Qt6 Qt5 REQUIRED COMPONENTS Widgets)
find_package(Qt${QT_VERSION_MAJOR} REQUIRED COMPONENTS Widgets)

add_executable(apng_generator
    main.cpp
    FrameItem.cpp
    ApngGenerator.cpp
    MainWindow.cpp
)

target_link_libraries(apng_generator PRIVATE Qt${QT_VERSION_MAJOR}::Widgets)

# 关键：设置为 Windows 图形界面程序，不显示控制台
set_target_properties(apng_generator PROPERTIES
    WIN32_EXECUTABLE TRUE
)