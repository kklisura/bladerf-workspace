#/bin/bash
set -e

CURRENT_DIR=$(pwd)

PYTHON_VIRTUALENV_DIR=python3.14
GNURADIO_SOURCE_DIR=$CURRENT_DIR/gnuradio/
BLADERF_SOURCE_DIR=$CURRENT_DIR/bladeRF/
GR_IQBAL_SOURCE_DIR=$CURRENT_DIR/gr-iqbal/
GR_OSMOSDR_SOURCE_DIR=$CURRENT_DIR/gr-osmosdr/
GR_BLADERF_SOURCE_DIR=$CURRENT_DIR/gr-bladeRF/
URH_SOURCE_DIR=$CURRENT_DIR/urh/

PATCHES_DIR=$CURRENT_DIR/patches/
OUTPUT_DIR=$CURRENT_DIR/output/

# Additional arguments passed to GENERATE, BUILD and INSTALL phase
#  --log-level=ERROR - increases log level threshold
#  -DCMAKE_RULE_MESSAGES=OFF - disables some messages
#  -DCMAKE_INSTALL_MESSAGE=NEVER - disables install/up-to-date based messages
#  GL_SILENCE_DEPRECATION - silence OpenGL deprecations
CMAKE_GENERATE_ADDITIONAL_ARGS="-DCMAKE_INSTALL_MESSAGE=NEVER \
                                -DCMAKE_RULE_MESSAGES=OFF \
                                -DCMAKE_C_FLAGS_INIT=\"-DGL_SILENCE_DEPRECATION\" \
                                -DCMAKE_CXX_FLAGS_INIT=\"-DGL_SILENCE_DEPRECATION\"
                                --log-level=ERROR"
CMAKE_BUILD_ADDITIONAL_ARGS="-- --silent"

apply_patches() {
    local prefix="$1"

    if [[ -z "$prefix" ]]; then
        echo "NOPE"
        return 1
    fi

    # Match: 001-prefix-*.patch
    local patches
    patches=$(ls -1 "$PATCHES_DIR"/[0-9][0-9][0-9]-"${prefix}"*.patch 2>/dev/null | sort -n)

    if [[ -z "$patches" ]]; then
        echo "  No patches present"
        return 0
    fi

    for patch in $patches; do
        # Only apply if it would apply cleanly
        if git apply --check "$patch" >/dev/null 2>&1; then
            echo "  $(basename "$patch"): Applied"
            git apply "$patch"
        else
            echo "     $(basename "$patch"): Failed to apply. Either it is applied or some other error."
        fi
    done
}

build_gnu_radio() {
  # Most of the following is adopted from https://github.com/Homebrew/homebrew-core/blob/5c8990d96e9ce7d5c1820e72798e18e85f95670e/Formula/g/gnuradio.rb

  echo "Building GNURadio..."

  cd $GNURADIO_SOURCE_DIR
  rm -rf build/ && mkdir build 

  local deps
  deps=(
    adwaita-icon-theme
    boost
    cppzmq
    fftw
    fmt
    gmp
    gsl
    gtk+3
    jack
    libsndfile
    libyaml
    numpy
    portaudio
    pygobject3
    pyqt@5
    python@3.14
    qt@5
    qwt-qt5
    rpds-py
    soapyrtlsdr
    soapysdr
    spdlog
    uhd
    volk
    zeromq
    pybind11
  )

  echo "  Installing dependencies..."

  for pkg in "${deps[@]}"; do
    if brew list --versions "$pkg" >/dev/null 2>&1; then
      echo "    - $pkg already installed"
    else
      echo "    - Installing $pkg..."
      brew install --quiet "$pkg" >/dev/null 2>&1
    fi
  done

  local python_deps
  python_deps=(
    click
    jsonschema
    lxml
    mako
    packaging
    pygccxml
    pyyaml
    setuptools
    pygobject
    scipy
    pyqtgraph
    numpy
  )

  echo "  Installing python dependencies..."

  for pkg in "${python_deps[@]}"; do
    if python3 -c "import $pkg" >/dev/null 2>&1; then
      echo "    - $pkg already installed"
    else
      echo "    - Installing $pkg..."
      pip install --quiet "$pkg" >/dev/null 2>&1
    fi
  done

  local python_site_packages
  local python_executable
  python_site_packages=$(python -c "import site; print(site.getsitepackages()[0])")
  python_executable=$(which python)
  external_site_packages=$(/opt/homebrew/opt/python@3.14/bin/python3.14 -c "import site; print(site.getsitepackages()[0])")

  # NOTE: We need this, so we can reuse the pyqt@5, gi from brew
  echo "$external_site_packages" > "$python_site_packages/pyqt5-brew.pth"
  echo "$external_site_packages" > "$python_site_packages/gi-brew.pth"

  local qwt_qt5_dir
  local qt5_dir
  qwt_qt5_dir=$(brew --prefix qwt-qt5)
  qt5_dir=$(brew --prefix qt@5)

  echo "  Generating build..."
  cmake -S . -B build $CMAKE_GENERATE_ADDITIONAL_ARGS \
    -Wno-dev \
    -Wno-deprecated-declarations \
    -Wno-unused-parameter \
    -DENABLE_GNURADIO_RUNTIME=ON \
    -DENABLE_GRC=ON \
    -DENABLE_PYTHON=ON \
    -DENABLE_GR_ANALOG=ON \
    -DENABLE_GR_AUDIO=ON \
    -DENABLE_GR_BLOCKS=ON \
    -DENABLE_GR_BLOCKTOOL=ON \
    -DENABLE_GR_CHANNELS=ON \
    -DENABLE_GR_DIGITAL=ON \
    -DENABLE_GR_DTV=ON \
    -DENABLE_GR_FEC=ON \
    -DENABLE_GR_FFT=ON \
    -DENABLE_GR_FILTER=ON \
    -DENABLE_GR_MODTOOL=ON \
    -DENABLE_GR_NETWORK=ON \
    -DENABLE_GR_QTGUI=ON \
    -DENABLE_GR_SOAPY=ON \
    -DENABLE_GR_TRELLIS=ON \
    -DENABLE_GR_UHD=ON \
    -DENABLE_GR_UTILS=ON \
    -DENABLE_GR_VOCODER=ON \
    -DENABLE_GR_WAVELET=ON \
    -DENABLE_GR_ZEROMQ=ON \
    -DENABLE_GR_PDU=ON \
    -DENABLE_NATIVE=ON \
    -DGR_PKG_CONF_DIR="$OUTPUT_DIR/etc/gnuradio/conf.d" \
    -DGR_PREFSDIR="$OUTPUT_DIR/etc/gnuradio/conf.d" \
    -DGR_PYTHON_DIR="$python_site_packages" \
    -DENABLE_DEFAULT=OFF \
    -DPYTHON_EXECUTABLE="$python_executable" \
    -DPYTHON_VERSION_MAJOR=3 \
    -DQWT_LIBRARIES="$qwt_qt5_dir/lib/qwt.framework/qwt" \
    -DQWT_INCLUDE_DIRS="$qwt_qt5_dir/lib/qwt.framework/Headers" \
    -DCMAKE_PREFIX_PATH="$qt5_dir/lib/cmake" \
    -DCMAKE_INSTALL_PREFIX="$OUTPUT_DIR"

  echo "  Building... (this may take a while)"
  cmake --build build $CMAKE_BUILD_ADDITIONAL_ARGS

  echo "  Installing..."
  cmake --install build
}

build_bladerf_cli() {
  echo "Building bladeRF CLI tool..."

  cd "$BLADERF_SOURCE_DIR"

  local deps
  deps=(
    libusb
    libtecla
    ncurses
  )

  echo "  Installing dependencies..."
 
  for pkg in "${deps[@]}"; do
    if brew list --versions "$pkg" >/dev/null 2>&1; then
      echo "    - $pkg already installed"
    else
      echo "    - Installing $pkg..."
      brew install --quiet "$pkg" >/dev/null 2>&1
    fi
  done

  cd host
  rm -rf build/ && mkdir build 

  echo "  Generating build..."
  cmake -S . -B build $CMAKE_GENERATE_ADDITIONAL_ARGS \
        -Wno-dev \
        -Wno-deprecated-declarations \
        -Wno-unused-parameter \
        -DENABLE_LIBTECLA=ON \
        -DENABLE_BACKEND_LIBUSB=ON \
        -DCMAKE_INSTALL_PREFIX="$OUTPUT_DIR"

  echo "  Building... (this may take a while)"
  cmake --build build $CMAKE_BUILD_ADDITIONAL_ARGS

  echo "  Installing..."
  cmake --install build

  echo "  Applying fixes..."
  # Some of the installed files should be relocated
  rm -rf "$OUTPUT_DIR/lib/cmake/bladeRF"
  mv "$OUTPUT_DIR/share/cmake/bladeRF" "$OUTPUT_DIR/lib/cmake/bladeRF"
  rm -rf "$OUTPUT_DIR/share/cmake"
}

build_gr_iqbal() {
  echo "Building gr-iqbal..."

  cd "$GR_IQBAL_SOURCE_DIR"

  local deps
  deps=(
    boost
    pybind11
  )

  echo "  Installing dependencies..."
 
  for pkg in "${deps[@]}"; do
    if brew list --versions "$pkg" >/dev/null 2>&1; then
      echo "    - $pkg already installed"
    else
      echo "    - Installing $pkg..."
      brew install --quiet "$pkg" >/dev/null 2>&1
    fi
  done

  echo "  Applying patches..."
  apply_patches "gr-iqbal"

  rm -rf build/ && mkdir build 

  local python_site_packages
  python_site_packages=$(python -c "import site; print(site.getsitepackages()[0])")

  echo "  Generating build..."
  cmake -S . -B build \
        -Wno-dev \
        -Wno-deprecated-declarations \
        -Wno-unused-parameter \
        -DGR_PYTHON_DIR="$python_site_packages" \
        -DPYTHON_LIBRARY="$OUTPUT_DIR/lib/libgnuradio-runtime.dylib" \
        -DCMAKE_INSTALL_PREFIX="$OUTPUT_DIR"

  echo "  Building..."
  cmake --build build $CMAKE_BUILD_ADDITIONAL_ARGS

  echo "  Installing..."
  cmake --install build
}

build_gr_osmosdr() {
  echo "Building gr-osmosdr..."

  cd "$GR_OSMOSDR_SOURCE_DIR"

  local python_deps
  python_deps=(
    six
    mako
    numpy
  )

  echo "  Installing python dependencies..."

  for pkg in "${python_deps[@]}"; do
    if python3 -c "import $pkg" >/dev/null 2>&1; then
      echo "    - $pkg already installed"
    else
      echo "    - Installing $pkg..."
      pip install --quiet "$pkg" >/dev/null 2>&1
    fi
  done

  echo "  Applying patches..."
  apply_patches "gr-osmosdr"

  rm -rf build/ && mkdir build 

  local python_executable
  local python_site_packages
  python_executable=$(which python)
  python_site_packages=$(python -c "import site; print(site.getsitepackages()[0])")

  echo "  Generating build..."
  cmake -S . -B build \
        -Wno-dev \
        -Wno-deprecated-declarations \
        -Wno-unused-parameter \
        -DGR_PYTHON_DIR="$python_site_packages" \
        -DQA_PYTHON_EXECUTABLE="$python_executable" \
        -DPYTHON_EXECUTABLE="$python_executable" \
        -DCMAKE_PREFIX_PATH="$OUTPUT_DIR/lib/cmake" \
        -DCMAKE_INSTALL_PREFIX="$OUTPUT_DIR"

  echo "  Building..."
  cmake --build build $CMAKE_BUILD_ADDITIONAL_ARGS

  echo "  Installing..."
  cmake --install build
}

build_gr_bladerf() {
  echo "Building gr-bladeRF..."

  cd "$GR_BLADERF_SOURCE_DIR"

  rm -rf build/ && mkdir build 

  local python_executable
  local python_executable
  python_executable=$(which python)
  python_site_packages=$(python -c "import site; print(site.getsitepackages()[0])")

  echo "  Generating build..."
  cmake -S . -B build \
        -Wno-dev \
        -Wno-deprecated-declarations \
        -Wno-unused-parameter \
        -DGR_PYTHON_DIR="$python_site_packages" \
        -DQA_PYTHON_EXECUTABLE="$python_executable" \
        -DPYTHON_EXECUTABLE="$python_executable" \
        -DCMAKE_PREFIX_PATH="$OUTPUT_DIR/lib/cmake" \
        -DCMAKE_INSTALL_PREFIX="$OUTPUT_DIR"

  echo "  Building..."
  cmake --build build $CMAKE_BUILD_ADDITIONAL_ARGS

  echo "  Installing..."
  cmake --install build
}

build_bladerf_gnuradio_blocks() {
  echo "Building bladeRF CLI tool..."

  build_gr_iqbal
  build_gr_osmosdr
  build_gr_bladerf
}

build_urh() {
  echo "Building urh (Universal Radio Hacker)..."

  cd "$URH_SOURCE_DIR"

  echo "  Installing python dependencies..."

  # The list of dependencies taken from https://github.com/jopohl/urh/blob/master/data/requirements.txt
  local python_deps
  python_deps=(
    pyqt5
    psutil
    cython
    setuptools
  )

  for pkg in "${python_deps[@]}"; do
    if python3 -c "import $pkg" >/dev/null 2>&1; then
      echo "    - $pkg already installed"
    else
      echo "    - Installing $pkg..."
      pip install --quiet "$pkg" >/dev/null 2>&1
    fi
  done

  echo "  Applying patches..."
  apply_patches "urh"

  echo "  Building..."

  rm -rf build/
  rm -rf src/build/
  rm -rf var/

  # Clean any previously generated cpp files
  rm -rf src/urh/dev/native/lib/*.cpp

  BLADERF_INCDIR="$OUTPUT_DIR/include" \
  BLADERF_LIBDIR="$OUTPUT_DIR/lib" \
  python setup.py --quiet install
}

ensure_brew() {
  echo "Ensuring Homebrew is installed..."

  if ! command -v brew >/dev/null 2>&1; then
    echo "  Homebrew is NOT installed or not in PATH"
    exit 1
  fi

  # Check brew accessibility and version
  if ! brew --version >/dev/null 2>&1; then
    echo "  'brew' command exists but cannot be executed properly"
    exit 1
  fi

  echo "  Homebrew found: $(brew --version | head -n1)"
  return 0
}

ensure_git() {
  echo "Ensuring Git is installed..."

  if ! command -v git >/dev/null 2>&1; then
    echo "  Git is NOT installed or not in PATH"
    exit 1
  fi

  # Check git accessibility and version
  if ! git --version >/dev/null 2>&1; then
    echo "  'git' command exists but cannot be executed properly"
    exit 1
  fi

  echo "  Git found: $(git --version)"
  return 0
}

ensure_python() {
  echo "Ensuring Python is available via virtualenv..."

  if [[ ! -d "$PYTHON_VIRTUALENV_DIR" ]]; then
      echo "  Directory '$PYTHON_VIRTUALENV_DIR' does not exist"
      exit 1
  fi

  if [[ ! -x "$PYTHON_VIRTUALENV_DIR/bin/python" ]]; then
      echo "  '$PYTHON_VIRTUALENV_DIR/bin/python' is missing or not executable"
      exit 1
  fi

  if ! "$PYTHON_VIRTUALENV_DIR/bin/python" -c "import sys; exit(0) if sys.version.startswith('3.14') else exit(1)" >/dev/null 2>&1; then
      echo "  Python version inside virtualenv is not 3.14"
      exit 1
  fi

  source "$PYTHON_VIRTUALENV_DIR/bin/activate"

  if command -v python3.14 >/dev/null 2>&1; then
    echo "  Python 3.14 is installed as python3: $(python3 --version)"
    return 0
  fi

  echo "  Python 3.14 virtualenv is not created."
  exit 1
}

ensure_cmake() {
  echo "Ensuring CMake is installed..."

  if ! command -v cmake >/dev/null 2>&1; then
    echo "  CMake is NOT installed or not in PATH"
    exit 1
  fi

  if ! cmake --version >/dev/null 2>&1; then
    echo "  'cmake' command exists but cannot be executed properly"
    exit 1
  fi

  echo "  CMake found: $(cmake --version | head -n1)"
  return 0
}

clean_output_dir() {
  rm -rf "$OUTPUT_DIR"
  mkdir "$OUTPUT_DIR"
  mkdir "$OUTPUT_DIR/etc/"
}

main() {
  ensure_git
  ensure_brew
  ensure_python
  ensure_cmake
  clean_output_dir
  build_gnu_radio
  build_bladerf_cli
  build_bladerf_gnuradio_blocks
  build_urh
}

main "$@"
