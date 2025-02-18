@echo off

if NOT "%1" == "x64" (
    echo Must specify first argument as x64
    goto :error
)
if "%1" == "x64" (
    set arch=64
    set cmake_gen="Visual Studio 16 2019"
)
if "%2" == "" (
    echo Must specify second argument as build config
    goto :error
)

set build_config=%2

set boost_dir=C:/local/boost_1_77_0
set boost_lib_dir=%boost_dir%/lib%arch%-msvc-14.1
set boost_installer="boost_1_77_0-msvc-14.1-%arch%.exe"
set boost_dl="https://iweb.dl.sourceforge.net/project/boost/boost-binaries/1.77.0/boost_1_77_0-msvc-14.1-%arch%.exe"

cd /D "%~dp0"
set start_dir=%cd%

if "%3" == "" (
    set source_dir=%start_dir%/solidity
) ELSE (
    set source_dir=%start_dir%/solidity-%3
)

echo Build directory %source_dir%

if exist %boost_lib_dir% (
    echo Boost already installed at %boost_lib_dir%, skipping download and install
)
if NOT exist %boost_lib_dir% (
    
    if exist %boost_installer% (
        echo Boost already downloaded: %boost_installer%
    )
    if NOT exist %boost_installer% (
        echo Downloading boost from %boost_dl%
        powershell -Command "Invoke-WebRequest %boost_dl% -OutFile %boost_installer%"
    )

    echo Installing boost...
    %boost_installer% /silent
)

cd %source_dir%

break>prerelease.txt

set build_output_dir=build-%build_config%-x%arch%

if exist "%build_output_dir%" (
    echo Cleaning build directory: %build_output_dir%
    powershell -Command "Remove-Item -Recurse -Force '%build_output_dir%'"
)
if NOT exist "%build_output_dir%" (
    mkdir "%build_output_dir%"
)

cd "%source_dir%/%build_output_dir%"

echo Patching libsolc cmake to build shared lib
set solc_cmake=%source_dir%/libsolc/CMakeLists.txt
echo %source_dir%/libsolc/CMakeLists.txt
powershell -Command "(gc %solc_cmake%) -replace 'libsolc libsolc.cpp', 'libsolc SHARED libsolc.cpp' | Out-File %solc_cmake% -encoding ASCII"

echo Creating cmake override to force static linking to runtime
set cxx_flag_overrides="%source_dir%/cmake/cxx_flag_overrides.cmake"
echo set(CMAKE_CXX_FLAGS_DEBUG_INIT          "/MT /Zi /Od /Ob0 /D NDEBUG")  >> %cxx_flag_overrides%
echo set(CMAKE_CXX_FLAGS_MINSIZEREL_INIT     "/MT /O1 /Ob1 /D NDEBUG")      >> %cxx_flag_overrides%
echo set(CMAKE_CXX_FLAGS_RELEASE_INIT        "/MT /O2 /Ob2 /D NDEBUG")      >> %cxx_flag_overrides%
echo set(CMAKE_CXX_FLAGS_RELWITHDEBINFO_INIT "/MT /Z7 /O2 /Ob1 /D NDEBUG")  >> %cxx_flag_overrides%
echo set(CXXFLAGS "${CXXFLAGS} /permissive-")                               >> %cxx_flag_overrides%
echo set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /permissive-")                 >> %cxx_flag_overrides%
echo set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} /permissive-") >> %cxx_flag_overrides%

echo Cmake generation for msvc solidity project
cmake -G %cmake_gen% .. ^
    -DTESTS=Off ^
    -DBOOST_ROOT="%boost_dir%" ^
    -DBoost_USE_STATIC_RUNTIME=ON ^
    -DBoost_USE_MULTITHREADED=OFF ^
    -DBoost_USE_STATIC_LIBS=ON ^
    -DCMAKE_SUPPRESS_REGENERATION=TRUE ^
    -DCMAKE_BUILD_TYPE=%build_config% ^
    -DCMAKE_WINDOWS_EXPORT_ALL_SYMBOLS=TRUE ^
    -DCMAKE_CXX_STANDARD=17 ^
    -DCMAKE_CXX_STANDARD_REQUIRED=ON ^
    -DCMAKE_USER_MAKE_RULES_OVERRIDE_CXX="%source_dir%/cmake/cxx_flag_overrides.cmake"

echo Building solidity solution
cd "%source_dir%/%build_output_dir%"
msbuild solidity.sln /t:libsolc /p:Configuration=%build_config% /m:%NUMBER_OF_PROCESSORS% /v:minimal

cd %start_dir%