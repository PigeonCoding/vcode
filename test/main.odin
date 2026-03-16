package test

import odin_builder "../libs/build_odin"
import "core:fmt"
import "core:os"
import "core:strings"

EXMP_FOLDER :: "examples"

examples :: []string{
  "hello.vc",
  "if.vc",
  "while.vc",
  "ops.vc",
  "pp_mm.vc",
  "struct.vc",
  "types.vc",
  "functions.vc",
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
  b.directory = "src"

  cmd := odin_builder.build_cmd(&b)
  if err, ok := odin_builder.exec_and_run_sync(cmd[:]).?; !ok {
    fmt.eprintln(err)
    return false
  }
  return true
}

compile_example :: proc(ex: string) -> bool {
  base := strings.trim_suffix(ex, ".vc")
  out_path := fmt.tprintf("build/%s", ex)
  in_file := fmt.tprintf("%s/%s", EXMP_FOLDER, ex)
  cmd := []string{"./build/vcode", in_file, "-o", out_path}
  if err, ok := odin_builder.exec_and_run_sync(cmd[:]).?; !ok {
    fmt.eprintln(err)
    return false
  }
  return true
}

main :: proc() {
  if !build_compiler() {
    os.exit(1)
  }

  for ex in examples {
    if !compile_example(ex) {
      os.exit(1)
    }
  }
}
