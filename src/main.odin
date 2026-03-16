package main

import "core:fmt"
import "core:os"
import "core:strings"
import flag "../libs/flags"
import lex "../libs/lexer"

usage :: proc(program: string, cont: ^flag.flag_container) {
  fmt.eprintfln("Usage: %s [OPTIONS] file.vc", program)
  fmt.eprintln("OPTIONS:")
  flag.print_usage(cont)
}

main :: proc() {
  init_compiler()

  cont: flag.flag_container
  cont.flags_map = make(map[string]^flag.flag_t)
  cont.skip_pogram_name = true
  
  flag.add_flag(&cont, "-help", false, "Print this help to stdout and exit with 0")
  flag.add_flag(&cont, "ssa", false, "Print generated C code to stdout")
  flag.add_flag(&cont, "s", false, "silences messages")
  flag.add_flag(&cont, "o", "out", "sets the output file (any flag has to be set before the input file)")

  flag.check_flags(&cont)

  help := false
  if v := flag.get_flag_value(&cont, "help"); v != nil {
    help = (cast(^bool)v)^
    usage(os.args[0], &cont)
  }
  ssa := false
  if v := flag.get_flag_value(&cont, "ssa"); v != nil {
    ssa = (cast(^bool)v)^
  }
  silent := false
  if v := flag.get_flag_value(&cont, "s"); v != nil {
    silent = (cast(^bool)v)^
  }
  outb := "out"
  if v := flag.get_flag_value(&cont, "o"); v != nil {
    outb = (cast(^string)v)^
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

  fmt.sbprintf(&output, "#include <stdbool.h>\n#include <stdint.h>\n#include <stdio.h>\n\n")

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
  out_str := strings.to_string(output)

  if ssa {
    fmt.println(out_str)
  }

  out_path := strings.concatenate({outb, ".c"})
  if err := os.write_entire_file(out_path, out_str); err != nil {
    fmt.eprintln(err)
    return
  }
  if !silent {
    fmt.printf("wrote generated C to %s\n", out_path)
  }
}
