package main

import lex "../libs/lexer"
import "core:fmt"
import "core:strings"

TypeTag :: enum u8 {
  invalid = 0,
  i32     = 'w',
  i64     = 'l',
  f32     = 's',
  f64     = 'd',
  u8      = 'u',
  u16     = 'v',
  i8      = 'c',
  i16     = 'h',
  bool    = 'o',
  ptr     = 'p',
  string_ = 'S',
  custom  = 'T',
}

VarType :: struct {
  tag    :    TypeTag,
  custom : string,
}

struct_types: map[string]bool
var_types: map[string]VarType
uses_dstring: bool

emit_var_decl_default :: proc(out: ^strings.Builder, type_name: string, var_name: string, tag: TypeTag, is_custom: bool) {
  if (is_custom && !is_function_typedef(type_name)) || tag == .string_ {
    fmt.sbprintf(out, "  %s %s = {{0}};\n", type_name, var_name)
  } else {
    fmt.sbprintf(out, "  %s %s = 0;\n", type_name, var_name)
  }
}

is_struct_type :: proc(type_name: string) -> bool {
  _, ok := struct_types[type_name]
  return ok
}

register_struct_type :: proc(type_name: string) {
  if _, ok := struct_types[type_name]; ok {
    return
  }
  struct_types[type_name] = true
}

resolve_decl_type :: proc(l: ^lex.lexer) -> (string, VarType, bool) {
  if l.token.type != .id {
    return "", VarType{}, false
  }
  switch l.token.str {
  case "i32":
    return "int32_t", VarType{.i32, ""}, true
  case "i64":
    return "int64_t", VarType{.i64, ""}, true
  case "f32":
    return "float", VarType{.f32, ""}, true
  case "f64":
    return "double", VarType{.f64, ""}, true
  case "u8", "byte", "ubyte":
    return "uint8_t", VarType{.u8, ""}, true
  case "u16":
    return "uint16_t", VarType{.u16, ""}, true
  case "i8":
    return "int8_t", VarType{.i8, ""}, true
  case "i16":
    return "int16_t", VarType{.i16, ""}, true
  case "bool":
    return "bool", VarType{.bool, ""}, true
  case "string":
    uses_dstring = true
    return "DString", VarType{.string_, ""}, true
  }

  if is_struct_type(l.token.str) {
    return l.token.str, VarType{.custom, l.token.str}, true
  }

  return "", VarType{}, false
}

type_tag_to_c :: proc(t: TypeTag) -> string {
  #partial switch t {
  case .i32:
    return "int32_t"
  case .i64:
    return "int64_t"
  case .f32:
    return "float"
  case .f64:
    return "double"
  case .u8:
    return "uint8_t"
  case .u16:
    return "uint16_t"
  case .i8:
    return "int8_t"
  case .i16:
    return "int16_t"
  case .bool:
    return "bool"
  case .ptr:
    return "const char *"
  case .string_:
    return "DString"
  case:
    return "int64_t"
  }
}

type_tag_is_integer :: proc(t: TypeTag) -> bool {
  return t == .i32 || t == .i64 || t == .u8 || t == .u16 || t == .i8 || t == .i16
}

type_tag_is_float :: proc(t: TypeTag) -> bool {
  return t == .f32 || t == .f64
}

type_tag_is_numeric :: proc(t: TypeTag) -> bool {
  return type_tag_is_integer(t) || type_tag_is_float(t)
}

join_numeric_types :: proc(lhs: TypeTag, rhs: TypeTag) -> TypeTag {
  if lhs == .f64 || rhs == .f64 do return .f64
  if lhs == .f32 || rhs == .f32 do return .f32
  if lhs == .i64 || rhs == .i64 do return .i64
  if lhs == .i32 || rhs == .i32 do return .i32
  if lhs == .u16 || rhs == .u16 do return .u16
  if lhs == .i16 || rhs == .i16 do return .i16
  if lhs == .u8 || rhs == .u8 do return .u8
  return .i8
}

type_is_assignable :: proc(
  lhs_tag: TypeTag,
  lhs_custom: string,
  rhs_tag: TypeTag,
  rhs_custom: string,
) -> bool {
  if lhs_tag == .custom || rhs_tag == .custom {
    if lhs_tag != .custom || rhs_tag != .custom do return false
    if lhs_custom == "" || rhs_custom == "" do return false
    return lhs_custom == rhs_custom
  }
  if lhs_tag == .string_ || rhs_tag == .string_ do return lhs_tag == rhs_tag
  if lhs_tag == .bool || rhs_tag == .bool do return lhs_tag == rhs_tag
  if lhs_tag == .ptr || rhs_tag == .ptr do return lhs_tag == rhs_tag
  if type_tag_is_numeric(lhs_tag) && type_tag_is_numeric(rhs_tag) do return true
  return lhs_tag == rhs_tag
}
