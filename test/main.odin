package test

import odin_builder "../libs/build_odin"
import "core:fmt"
import "core:os"
import "core:strings"

examples :: []string{
  "examples/hello.vc",
  "examples/if.vc",
  "examples/while.vc",
  "examples/ops.vc",
  "examples/pp_mm.vc",
  "examples/struct.vc",
  "examples/types.vc",
  "examples/functions.vc",
}

build_compiler :: proc() -> bool {
  b: odin_builder.odin_cmd_builder
  b.main_cmd = .build
  if ODIN_OS == .Linux {
    b.flags.out = "build/vcode"
  } else if ODIN_OS == .Windows {
    b.flags.out = "build/vcode.exe"
  } else {
    fmt.eprintln("unsupported OS")
    return false
  }
  b.flags.debug = true
  b.directory = "src_odin"

  cmd := odin_builder.build_cmd(&b)
  if err, ok := odin_builder.exec_and_run_sync(cmd[:]).?; !ok {
    fmt.eprintln(err)
    return false
  }
  return true
}

compile_example :: proc(ex: string) -> bool {
  base := strings.trim_suffix(ex, ".vc")
  out_path := fmt.tprintf("build/tests/%s", base)
  cmd := []string{"./build/vcode", "-o", out_path, ex}
  if err, ok := odin_builder.exec_and_run_sync(cmd[:]).?; !ok {
    fmt.eprintln(err)
    return false
  }
  return true
}

main :: proc() {
  if err := os.make_directory_all("build/tests"); err != nil {
    // fmt.eprintln(err)
    // os.exit(1)
  }

  // if !build_compiler() {
  //   os.exit(1)
  // }

  for ex in examples {
    if !compile_example(ex) {
      os.exit(1)
    }
  }
}
