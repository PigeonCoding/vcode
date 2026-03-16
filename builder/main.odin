package builder

import odin_builder "../libs/build_odin"
import "core:fmt"
import "core:os"

main :: proc() {
  b: odin_builder.odin_cmd_builder
  b.main_cmd = .build
  if ODIN_OS == .Linux {
    b.flags.out = "build/vcode"
  } else if ODIN_OS == .Windows {
    b.flags.out = "build/vcode.exe"
  } else {
    fmt.println("unsupported OS")
    os.exit(1)
  }
  b.flags.debug = true
  b.directory = "src_odin"

  cmd := odin_builder.build_cmd(&b)
  if err, ok := odin_builder.exec_and_run_sync(cmd[:]).?; !ok {
    fmt.eprintln(err)
    os.exit(1)
  }
  if ODIN_OS == .Windows {
    odin_builder.exec_and_run_async([]string{"rm", os.args[0]})
  }
}
