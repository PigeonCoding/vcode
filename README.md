# A Small Compiled Programming Language

## Requirements
- `odin` # tested on `odin version dev-2026-03:1a5126c6b` anything newer should work but not older
- `gcc` or `clang` (`cl` is experimental and not tested) in your path (alternatively set the -cc flags ex: ./vcode -cc /your/path/compiler )

## How to build
```console
$ odin run ./builder
$ odin run ./test # to build all the examples
$ ./vcode -o hello examples/hello.vc
```
