package builder

import odin_builder "../libs/build_odin"
import "core:fmt"
import "core:os"

main :: proc() {
  // QBE backend as a static library (linked by the libs/qbe Odin wrapper).
  // QBE is POSIX-only C (getopt.h), so skip it on Windows for now.
  if ODIN_OS == .Windows {
    fmt.println("warning: skipping libqbe.a build on Windows (QBE needs a POSIX toolchain)")
  } else {
    lib_cmd := []string{"make", "-C", "libs/qbe", "-f", "Makefile.lib", "libqbe.a"}
    if err, ok := odin_builder.exec_and_run_sync(lib_cmd[:]).?; ok {
      fmt.eprintln("failed to build libqbe.a:", err)
      os.exit(1)
    }
  }

  b: odin_builder.odin_cmd_builder
  b.main_cmd = .build
  if ODIN_OS == .Linux {
    b.flags.out = "vcode"
  } else if ODIN_OS == .Windows {
    b.flags.out = "vcode.exe"
  } else {
    fmt.println("unsupported OS")
    os.exit(1)
  }
  b.flags.debug = true
  b.directory = "src"

  cmd := odin_builder.build_cmd(&b)
  if err, ok := odin_builder.exec_and_run_sync(cmd[:]).?; ok {
    fmt.eprintln(err)
  }
}
