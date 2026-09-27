package vcode

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
  cont: flag.flag_container
  cont.flags_map = make(map[string]^flag.flag_t)
  cont.skip_pogram_name = true

  flag.add_flag(&cont, "-help", false, "Print this help to stdout and exit with 0")
  flag.check_flags(&cont)

  help := false
  if v := flag.get_flag_value(&cont, "help"); v != nil {
    help = (cast(^bool)v)^
    usage(os.args[0], &cont)
  }

  if help {
    usage(os.args[0], &cont)
    return
  }

}
