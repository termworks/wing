# Installation

Build locally with the repo recipes (`.make.lua`, via [oslo](https://github.com/termworks/oslo)):

```sh
make build
```

The binary is written to `./wing`.

Run the local verification gate:

```sh
make verify
make build
make clean
```

Install into `~/.local/bin`:

```sh
make install
```
