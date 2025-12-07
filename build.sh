#/bin/bash

CURRENT_DIR=$(pwd)

PYTHON_VIRTUALENV_DIR=python3.14
GNURADIO_SOURCE_DIR=$CURRENT_DIR/gnuradio/
BLADERF_SOURCE_DIR=$CURRENT_DIR/bladeRF/
GR_IQBAL_SOURCE_DIR=$CURRENT_DIR/gr-iqbal/
GR_OSMOSDR_SOURCE_DIR=$CURRENT_DIR/gr-osmosdr/
GR_BLADERF_SOURCE_DIR=$CURRENT_DIR/gr-bladeRF/

PATCHES_DIR=$CURRENT_DIR/patches/
OUTPUT_DIR=$CURRENT_DIR/output/

# Additional arguments passed to GENERATE, BUILD and INSTALL phase
#  -Wno-dev - disables some dev warnings
#  --log-level=ERROR - increases log level threshold
#  -DCMAKE_RULE_MESSAGES=OFF - disables some messages
#  -DCMAKE_INSTALL_MESSAGE=NEVER - disables install/up-to-date based messages
#  -DGL_SILENCE_DEPRECATION - silence OpenGL deprecations
#  -Wdeprecated-declarations - generally disable deprecation warnings
CMAKE_GENERATE_ADDITIONAL_ARGS="-DCMAKE_INSTALL_MESSAGE=NEVER -DCMAKE_RULE_MESSAGES=OFF -DGL_SILENCE_DEPRECATION -Wdeprecated-declarations -Wno-dev --log-level=ERROR"
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
  
  # NOTE: We need this, so we can reuse the pyqt@5 libraries
  echo "/opt/homebrew/lib/python3.14/site-packages" > "$site_dir/pyqt5-brew.pth"

  local qwt_qt5_dir
  local qt5_dir
  qwt_qt5_dir=$(brew --prefix qwt-qt5)
  qt5_dir=$(brew --prefix qt@5)

  echo "  Generating build..."
  cmake -S . -B build $CMAKE_GENERATE_ADDITIONAL_ARGS \
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

  echo "  Generating build..."
  cmake -S . -B build \
        -DCMAKE_INSTALL_PREFIX="$OUTPUT_DIR"

  echo "  Building..."
  cmake --build build $CMAKE_BUILD_ADDITIONAL_ARGS

  echo "  Installing..."
  cmake --install build

  echo "  Applying fixes..."
  # Some of the installed files should be relocated
  local python_executable
  python_site_packages=$(python -c "import site; print(site.getsitepackages()[0])")

  rm -rf "$python_site_packages/gnuradio/iqbalance"
  mv "$OUTPUT_DIR/lib/python3.14/site-packages/gnuradio/iqbalance" "$python_site_packages/gnuradio/iqbalance"
  rm -rf "$OUTPUT_DIR/lib/python3.14"
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
  python_executable=$(which python)

  echo "  Generating build..."
  cmake -S . -B build \
        -DQA_PYTHON_EXECUTABLE="$python_executable" \
        -DPYTHON_EXECUTABLE="$python_executable" \
        -DCMAKE_PREFIX_PATH="$OUTPUT_DIR/lib/cmake" \
        -DCMAKE_INSTALL_PREFIX="$OUTPUT_DIR"

  echo "  Building..."
  cmake --build build $CMAKE_BUILD_ADDITIONAL_ARGS

  echo "  Installing..."
  cmake --install build

  echo "  Applying fixes..."
  # Some of the installed files should be relocated
  local python_executable
  python_site_packages=$(python -c "import site; print(site.getsitepackages()[0])")

  rm -rf "$python_site_packages/osmosdr"
  mv "$OUTPUT_DIR/lib/python3.14/site-packages/osmosdr" "$python_site_packages/osmosdr"
  rm -rf "$OUTPUT_DIR/lib/python3.14"
}

build_gr_bladerf() {
  echo "Building gr-bladeRF..."

  cd "$GR_BLADERF_SOURCE_DIR"

  rm -rf build/ && mkdir build 

  local python_executable
  python_executable=$(which python)

  echo "  Generating build..."
  cmake -S . -B build \
        -DPKG_CONFIG_PATH="$OUTPUT_DIR/lib/pkgconfig" \
        -DQA_PYTHON_EXECUTABLE="$python_executable" \
        -DPYTHON_EXECUTABLE="$python_executable" \
        -DCMAKE_PREFIX_PATH="$OUTPUT_DIR/lib/cmake" \
        -DCMAKE_INSTALL_PREFIX="$OUTPUT_DIR"

  echo "  Building..."
  cmake --build build $CMAKE_BUILD_ADDITIONAL_ARGS

  echo "  Installing..."
  cmake --install build

  echo "  Applying fixes..."
  # Some of the installed files should be relocated
  local python_executable
  python_site_packages=$(python -c "import site; print(site.getsitepackages()[0])")

  rm -rf "$python_site_packages/bladeRF"
  mv "$OUTPUT_DIR/lib/python3.14/site-packages/bladeRF" "$python_site_packages/bladeRF"
  rm -rf "$OUTPUT_DIR/lib/python3.14"
}

build_bladerf_gnuradio_blocks() {
  echo "Building bladeRF CLI tool..."

  build_gr_iqbal
  build_gr_osmosdr
  build_gr_bladerf
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
    echo "  Python 3.14 is installed: $(python3.14 --version)"
    return 0
  fi

  # Fallback: user may only have "python3" but with version 3.14
  if command -v python3 >/dev/null 2>&1; then
    local ver
    ver="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "")"
    if [[ "$ver" == "3.14" ]]; then
      echo "  Python 3.14 is installed as python3: $(python3 --version)"
      return 0
    fi
  fi

  echo "  Python 3.14 is NOT installed."
  exit 1
}

clean_output_dir() {
  rm -rf "$OUTPUT_DIR"
  mkdir "$OUTPUT_DIR"
  mkdir "$OUTPUT_DIR/etc/"
}

main() {
  ensure_python
  clean_output_dir
  build_gnu_radio
  build_bladerf_cli
  build_bladerf_gnuradio_blocks
}

main "$@"