# yosys-opensta

Use open-source EDA tools for ASIC synthesis ([YosysHQ/yosys](https://github.com/YosysHQ/yosys)) and timing analysis ([parallaxsw/OpenSTA](https://github.com/parallaxsw/OpenSTA)), to understand the timing situation of the front-end RTL design and iterate quickly.

Inspired by [OSCPU/yosys-sta](https://github.com/OSCPU/yosys-sta).

## Denpendency and Environment

Firstly, install the [Docker](https://www.docker.com/) for [parallaxsw/OpenSTA](https://github.com/parallaxsw/OpenSTA).

```shell
apt install -y yosys docker
# or
brew install yosys docker
# or
# https://github.com/YosysHQ/oss-cad-suite-build

make init
```

## Usage Example

```shell
# run sta and show result with default gcd.v
make sta show

# run sta with custom frequency with default gcd.v
make sta CLK_FREQ_MHZ=100

# run with custom design
make sta DESIGN=top_of_design RTL_FILES="/path/to/top.v /path/to/perip.v ..." CLK_FREQ_MHZ=100
```

## Documentation

See the source code or [OSCPU/yosys-sta](https://github.com/OSCPU/yosys-sta).

## Reference & Acknowledgement
- [OSCPU/yosys-sta](https://github.com/OSCPU/yosys-sta)
- [YosysHQ/yosys: Yosys Open SYnthesis Suite](https://github.com/YosysHQ/yosys)
- [parallaxsw/OpenSTA](https://github.com/parallaxsw/OpenSTA)
