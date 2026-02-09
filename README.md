# multimodal

Watch logs of all the [Modal](https://modal.com/) apps in a single environment.

## Usage

To install `multimodal` with [LuaRocks](https://luarocks.org), use:

```bash
luarocks install --server=https://luarocks.org/dev terminal
luarocks install https://raw.githubusercontent.com/catwell/multimodal/refs/heads/main/rockspec/multimodal-dev-1.rockspec
```

Run `multimodal` with the Modal environment name:

```bash
multimodal -e my-modal-env
```

Press `Ctrl+C` to exit.

> Note: This is only tested on Linux. You need the `modal` CLI installed.

## Development

This project is written in [Teal](https://teal-language.org), a typed dialect of Lua.

> Note: Coding agents are used to assist with the development of this tool (in other words it is mostly vibe-coded).

To bootstrap the local development environment, run:

```bash
curl https://loadk.com/localua.sh -O
sh localua.sh .lua
./.lua/bin/luarocks install tl
./.lua/bin/luarocks install --server=https://luarocks.org/dev terminal
./.lua/bin/luarocks install --only-deps rockspec/multimodal-dev-1.rockspec
```

To rebuild and install the Lua version, use:

```bash
tl gen multimodal.tl
./.lua/bin/luarocks make
```

To test without running modal jobs you can use `fakemodal`:

```bash
./.lua/bin/lua multimodal.lua -e test -m "./.lua/bin/tl run fakemodal.tl --"
```

## Copyright

Copyright (c) from 2026 Pierre Chapuis

Some definition files in `tealtypes` are copied from [Teal Types](https://github.com/teal-language/teal-types).
