# Power, Performance, and Area (PPA) Estimation Benchmarks

## Usage

Evaluate target IP cores placed in the [third_party](third_party) directory. See its [README.md](third_party/README.md) for more details.

```shell
# Synthesis + STA only
make sta-hazard3
make sta-picorv32
make sta-serv

# Full flow (syn → sta → pnr)
make flow-hazard3
make flow-picorv32
make flow-serv

# Use ASAP7 platform
make sta-hazard3 PLATFORM=asap7

# Hierarchical synthesis
make sta-hazard3 SYNTH_HIERARCHICAL=1

# Custom clock frequency
make flow-picorv32 CLK_FREQ_MHZ=100
```

## Benchmark Pre-Generated Results

See the [results](results) directory.
