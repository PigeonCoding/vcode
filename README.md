# A Small Compiled Programming Language

## Requirements
- `odin` # tested on `odin version dev-2026-03:1a5126c6b` anything newer should work but not older
- `gcc` or `clang` (`cl` is experimental and not tested) in your path (alternatively set the -cc flags ex: ./vcode -cc /your/path/compiler )
- `qbe` v1.3 (vendored in `libs/qbe`)

`odin run ./builder` builds `libqbe.a` automatically (POSIX only; skipped
with a warning on Windows). Manually:
```console
$ make -C libs/qbe -f Makefile.lib libqbe.a
$ make -C libs/qbe # only if you also want the standalone `qbe` binary
```

The `qbe` Odin package (`libs/qbe/qbe.odin`) wraps `qbe_lib.h`: `compile_file`,
`compile_text`, `compile_to_builder` (assembly appended to a
`strings.Builder`), `compile_to_string`, `default_target`, `set_debug.

## How to build
```console
$ odin run ./builder
$ odin run ./test # to build all the examples
$ ./vcode -o hello examples/hello.vc
```
