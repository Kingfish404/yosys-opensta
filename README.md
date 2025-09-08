# yosys-opensta

Use open-source EDA tools for ASIC synthesis ([YosysHQ/yosys](https://github.com/YosysHQ/yosys)) and timing analysis ([parallaxsw/OpenSTA](https://github.com/parallaxsw/OpenSTA)), to understand the timing situation of the front-end RTL design and iterate quickly.

Inspired by [OSCPU/yosys-sta](https://github.com/OSCPU/yosys-sta).

## Denpendency and Environment

Firstly, install [YosysHQ](https://github.com/YosysHQ/yosys), and the [Docker](https://www.docker.com/) for [parallaxsw/OpenSTA](https://github.com/parallaxsw/OpenSTA). Then `make init` to get `nangate45` and `OpenSTA` docker images.

```shell
apt install -y yosys docker
# or
brew install yosys docker
# or
# https://github.com/YosysHQ/oss-cad-suite-build

make init

# install yosys-slang
git clone --recursive https://github.com/povik/yosys-slang
cd yosys-slang
make -j$(nproc)
make install
```

## Usage Example

```shell
# run sta and show result with default gcd.v
make sta show

# run sta with custom frequency with default gcd.v
make sta CLK_FREQ_MHZ=100

# run with custom design
make sta DESIGN=top_of_design RTL_FILES="/path/to/top.v /path/to/perip.v ..." VERILOG_INCLUDE_DIRS="/path/to/top.vh" CLK_FREQ_MHZ=100

# support system verilog
make sta DESIGN=top_of_design RTL_FILES="/path/to/top.sv /path/to/perip.sv ..." VERILOG_INCLUDE_DIRS="/path/to/top.svh" CLK_FREQ_MHZ=500
# or see the example `Makefile` in the `benchmark/`
```

Hint: Don't forget to remove the `DPI-C` and `$` macro related code in the system verilog file.

## Documentation

See the source code or [OSCPU/yosys-sta](https://github.com/OSCPU/yosys-sta).

## Benchmark

See the [benchmark](benchmark) directory. And the [third_party IP cores](benchmark/third_party/README.md).

## Reference & Acknowledgement
- [OSCPU/yosys-sta](https://github.com/OSCPU/yosys-sta)
- [YosysHQ/yosys: Yosys Open SYnthesis Suite](https://github.com/YosysHQ/yosys)
- [parallaxsw/OpenSTA](https://github.com/parallaxsw/OpenSTA)
