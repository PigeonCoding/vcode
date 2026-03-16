# A Small Compiled Programming Language

## Requirements
- `odin`
- `gcc` or `clang` in yout path

## How to build
```console
$ odin run ./builder
$ odin run ./test # to build all the examples
$ ./build/vcode -o examples/hello examples/hello.vc
```

The compiler currently generates C source (`.c`) output.
