# yosys-opensta

Use open-source EDA tools for ASIC synthesis ([YosysHQ/yosys](https://github.com/YosysHQ/yosys)) and timing analysis ([parallaxsw/OpenSTA](https://github.com/parallaxsw/OpenSTA)), to understand the timing situation of the front-end RTL design and iterate quickly.

Inspired by [OSCPU/yosys-sta](https://github.com/OSCPU/yosys-sta).

## Dependency and Environment

Install [YosysHQ/yosys](https://github.com/YosysHQ/yosys) first, then choose **one** of the following setup methods:

### Option A: Local build (no Docker)

`make init_local` will download and build CUDD, NANGATE45, OpenSTA, and yosys-slang in one step:

```shell
apt install -y yosys  # or: brew install yosys
make init_local
```

### Option B: Docker-based

```shell
apt install -y yosys docker  # or: brew install yosys docker
make init_opensta  # clone OpenSTA and build Docker image
make init          # download NANGATE45

# install yosys-slang manually
git clone --recursive https://github.com/povik/yosys-slang
cd yosys-slang && make -j$(nproc) && make install
```

## Usage Example

```shell
# run sta (Docker) and show result with default gcd.v
make sta show

# run sta locally (no Docker) and show result
make sta_local show

# run sta with custom frequency with default gcd.v
make sta CLK_FREQ_MHZ=100

# run with custom design
make sta DESIGN=top_of_design RTL_FILES="/path/to/top.v /path/to/perip.v ..." VERILOG_INCLUDE_DIRS="/path/to/top.vh" CLK_FREQ_MHZ=100

# support system verilog
make sta DESIGN=top_of_design RTL_FILES="/path/to/top.sv /path/to/perip.sv ..." VERILOG_INCLUDE_DIRS="/path/to/top.svh" CLK_FREQ_MHZ=500

# detailed timing report (Docker / local)
make sta_detail
make sta_detail_local

# generate dot diagrams (default svg, or specify format)
make dot
make dot DOT_FORMAT=svg

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
