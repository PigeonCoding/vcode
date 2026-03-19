package vcode

import "core:strings"
import "core:fmt"
import "core:os"
import build_odin "../libs/build_odin"
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

run_command_sync :: proc(cmd: []string) -> bool {
  if _, not_ok := build_odin.exec_and_run_sync(cmd).?; not_ok {
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
  if ODIN_OS == .Windows {
    if command_works_msvc("cl") do return "cl", true
  }
  if command_works("gcc") do return "gcc", true
  if command_works("clang") do return "clang", true
  return "", false
}

// ----------------------------------------------------

emit_c_escaped_string :: proc(out: ^strings.Builder, s: string) {
  fmt.sbprintf(out, "\"")
  for b in s {
    switch b {
    case '\\':
      fmt.sbprintf(out, "\\\\")
    case '"':
      fmt.sbprintf(out, "\\\"")
    case '\n':
      fmt.sbprintf(out, "\\n")
    case '\r':
      fmt.sbprintf(out, "\\r")
    case '\t':
      fmt.sbprintf(out, "\\t")
    case:
      fmt.sbprintf(out, "%c", b)
    }
  }
  fmt.sbprintf(out, "\"")
}

emit_source_line :: proc(out: ^strings.Builder, l: ^lex.lexer) {
  if l.file == "" || l.token.row == 0 {
    return
  }
  fmt.sbprintf(out, "#line %d ", l.token.row)
  emit_c_escaped_string(out, l.file)
  fmt.sbprintf(out, "\n")
}

reset_lexer :: proc(l: ^lex.lexer) {
  l.cursor = 0
  l.row = 0
  l.col = 0
  l.token = lex.token{}
}

get_keyword :: proc(l: ^lex.lexer) -> VC_Kws {
  if l.token.type != .id do return .none
  switch l.token.str {
  case "let":
    return .let
  case "if":
    return .if_
  case "while":
    return .while
  case "fn":
    return .fn
  case "struct":
    return .struct_
  }
  return .none
}

get_punct :: proc(l: ^lex.lexer) -> VC_Puncts {
  switch l.token.type {
  case .eq:
    return .eq
  case .plusplus:
    return .pp
  case .minusminus:
    return .mm
  case .punct:
    ch := byte(l.token.intlit)
    switch ch {
    case '+':
      return .add
    case '-':
      return .sub
    case '*':
      return .mult
    case '/':
      return .div
    case '%':
      return .mod
    case '=':
      return .assign
    case '<':
      return .less
    case '>':
      return .greater

    }

    if ch == '{' {
      for lex.get_token(l) {
        if l.token.type == .punct && byte(l.token.intlit) == '}' {
          break
        }
        if main_pass(l, false) {
          return .error
        }
      }
      lex.get_token(l)
    }

    if ch == '(' {
      for lex.get_token(l) {
        if l.token.type == .punct && byte(l.token.intlit) == ')' {
          break
        }
        if main_pass(l, false) {
          return .error
        }
      }
      lex.get_token(l)
    }
      case .none:
    case .either_end_or_failure:
    case .intlit:
    case .charlit:
    case .floatlit:
    case .id:
    case .dqstring:
    case .sqstring:
    case .notq:
    case .lesseq:
    case .greatereq:
    case .andand:
    case .oror:
    case .shl:
    case .shr:
    case .pluseq:
    case .minuseq:
    case .multeq:
    case .diveq:
    case .modeq:
    case .andeq:
    case .oreq:
    case .xoreq:
    case .arrow:
    case .eqarrow:
    case .shleq:
    case .shreq:

  }
  return .none
}
