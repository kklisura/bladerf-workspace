# BladeRF Workspace for OSX/macOS

## Setup

1. Install prerequisite:

    1. [brew](https://brew.sh)

    2. cmake

    3. python 3.14

Install cmake via brew by running:

```sh
brew install cmake
```

Install python via brew by running:

```sh
brew install python@3.14
```

Make sure prerequisite are installed:

```sh
> brew --version
Homebrew 5.0.5-53-g3419bb5
```

```sh
> git --version
git version 2.51.0
```

```sh
> cmake --version
cmake version 4.1.2
```

```sh
> python3.14 --version
Python 3.14.1
```

2. Clone the repository

```sh
git clone https://github.com/kklisura/bladerf-workspace.git
```

3. Update the submodules

```sh
cd bladerf-workspace
git submodule update --init --recursive
```

4. Setup python virtualenv

```sh
python3.14 -m venv python3.14

source python3.14/bin/activate
```

5. Run build script

```sh
./build.sh
```