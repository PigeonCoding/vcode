package main

import "core:fmt"
import "core:os"
import "core:strings"
import build_odin "../libs/build_odin"
import flag "../libs/flags"
import lex "../libs/lexer"

normalize_slashes :: proc(s: string) -> string {
  b: strings.Builder
  strings.builder_init(&b)
  for i := 0; i < len(s); i += 1 {
    ch := s[i]
    if ch == '\\' {
      fmt.sbprintf(&b, "/")
    } else {
      fmt.sbprintf(&b, "%c", ch)
    }
  }
  return strings.to_string(b)
}

usage :: proc(program: string, cont: ^flag.flag_container) {
  fmt.eprintfln("Usage: %s [OPTIONS] file.vc", program)
  fmt.eprintln("OPTIONS:")
  flag.print_usage(cont)
}

run_command_sync :: proc(cmd: []string) -> bool {
  // ok is true when an error value is present
  if _, ok := build_odin.exec_and_run_sync(cmd).?; ok {
    return false
  }
  return true
}

run_process_sync :: proc(cmd: []string) -> bool {
  procc: os.Process_Desc
  procc.stderr = os.stderr
  procc.stdout = os.stdout
  procc.env = nil
  procc.working_dir = ""

  procc.command = cmd
  p, err := os.process_start(procc)
  if err != nil do return false
  ps, err2 := os.process_wait(p)
  if err2 != nil do return false
  if ps.exit_code != 0 do return false
  return true
}

command_works :: proc(cmd: string) -> bool {
  if ODIN_OS == .Windows {
    return run_process_sync([]string{"cmd", "/C", strings.concatenate({cmd, " --version >NUL 2>&1"})})
  }
  return run_process_sync([]string{"sh", "-c", strings.concatenate({cmd, " --version >/dev/null 2>&1"})})
}

command_works_msvc :: proc(cmd: string) -> bool {
  if ODIN_OS != .Windows {
    return false
  }
  return run_process_sync([]string{"cmd", "/C", strings.concatenate({cmd, " /? >NUL 2>&1"})})
}

is_msvc_compiler :: proc(name: string) -> bool {
  if name == "cl" || name == "cl.exe" {
    return true
  }
  if strings.has_suffix(name, "\\cl.exe") || strings.has_suffix(name, "/cl.exe") {
    return true
  }
  if strings.has_suffix(name, "\\cl") || strings.has_suffix(name, "/cl") {
    return true
  }
  return false
}

resolve_compiler :: proc(override: string) -> (string, bool) {
  if override != "" {
    if ODIN_OS == .Windows && is_msvc_compiler(override) {
      if command_works_msvc(override) do return override, true
      return "", false
    }
    if command_works(override) do return override, true
    return "", false
  }
  if command_works("gcc") do return "gcc", true
  if command_works("clang") do return "clang", true
  if ODIN_OS == .Windows {
    if command_works_msvc("cl") do return "cl", true
  }
  return "", false
}

main :: proc() {
  init_compiler()

  cont: flag.flag_container
  cont.flags_map = make(map[string]^flag.flag_t)
  cont.skip_pogram_name = true
  
  flag.add_flag(&cont, "-help", false, "Print this help to stdout and exit with 0")
  flag.add_flag(&cont, "s", false, "silences messages")
  flag.add_flag(&cont, "o", "out", "sets the output file")
  flag.add_flag(&cont, "cc", "", "sets the compiler path (overrides auto-detect)")

  flag.check_flags(&cont)

  help := false
  if v := flag.get_flag_value(&cont, "help"); v != nil {
    help = (cast(^bool)v)^
    usage(os.args[0], &cont)
  }
  silent := false
  if v := flag.get_flag_value(&cont, "s"); v != nil {
    silent = (cast(^bool)v)^
  }
  outb := "out"
  if v := flag.get_flag_value(&cont, "o"); v != nil {
    outb = (cast(^string)v)^
  }
  compiler_override := ""
  if v := flag.get_flag_value(&cont, "cc"); v != nil {
    compiler_override = (cast(^string)v)^
  }

  if help {
    usage(os.args[0], &cont)
    return
  }

  file := ""
  for arg in cont.remaining {
    if strings.has_suffix(arg, ".vc") {
      file = arg
      break
    }
  }
  if file == "" {
    fmt.eprintln("please provide a source file")
    return
  }

  l := lex.init_lexer(file)

  if !silent {
    fmt.println("prepass")
  }
  if prepass(&l) {
    return
  }

  if len(typedef_output.buf) > 0 {
    fmt.sbprintf(&output, "\n%s\n", strings.to_string(typedef_output))
  }

  fmt.sbprint(&output, "int main(void) {\n")
  if !silent {
    fmt.println("main pass")
  }
  for lex.get_token(&l) {
    if main_pass(&l, false) {
      return
    }
  }

  fmt.sbprintf(&output, "\n  return 0;\n}\n")

  final_output: strings.Builder
  strings.builder_init(&final_output)
  fmt.sbprintf(&final_output, "#include <stdbool.h>\n#include <stdint.h>\n#include <stdio.h>\n")
  if uses_dstring {
    p, _ := os.get_executable_directory(context.allocator)
    libs_path := normalize_slashes(strings.concatenate({p, "/std/dstring.h"}))
    fmt.sbprintf(&final_output, "#define DSTRING_IMPLEMENTATION\n#include \"%s\"\n", libs_path)
  }
  fmt.sbprintf(&final_output, "\n%s", strings.to_string(output))
  out_str := strings.to_string(final_output)
  
  out_path := strings.concatenate({outb, ".c"})
  if err := os.write_entire_file(out_path, out_str); err != nil {
    fmt.eprintln(err)
    return
  }
  // defer { _ = os.remove(out_path) }
  if !silent {
    fmt.printf("generated C code \n")
  }

  compiler, ok := resolve_compiler(compiler_override)
  if !ok {
    if compiler_override != "" {
      fmt.eprintfln("compiler not found or failed to run: '%s'", compiler_override)
    } else {
      if ODIN_OS == .Windows {
        fmt.eprintln("no C compiler found in PATH (tried gcc, clang, then cl)")
      } else {
        fmt.eprintln("no C compiler found in PATH (tried gcc then clang)")
      }
    }
    os.exit(1)
  }

  if !silent {
    fmt.printf("compiling %s -> %s\n", out_path, outb)
  }
  
  compile_cmd: []string
  if is_msvc_compiler(compiler) {
    compile_cmd = []string{compiler, "/nologo", out_path, strings.concatenate({"/Fe:", outb})}
  } else {
    compile_cmd = []string{compiler, out_path, "-o", outb}
  }
  if !run_command_sync(compile_cmd) {
    fmt.eprintln("C compilation failed")
    return
  }
  if !silent {
    fmt.printf("wrote binary to %s\n", outb)
  }
}
