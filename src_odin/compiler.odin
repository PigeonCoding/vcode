package main

import lex "../libs/lexer"
import "core:fmt"
import "core:strings"

VC_Puncts :: enum {
	none,
	error,
	add,
	eq,
	assign,
	sub,
	mod,
	div,
	mult,
	pp,
	mm,
	less,
	greater,
}

VC_Kws :: enum {
	none,
	let,
	while,
	if_,
	fn,
	struct_,
}

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
	custom  = 'T',
}

VarType :: struct {
	tag:    TypeTag,
	custom: string,
}

Counter :: struct {
	index:    int,
	type_tag: TypeTag,
}

counter: Counter

last_lvalue: string
has_last_lvalue: bool
last_lvalue_tag: TypeTag
last_lvalue_custom: string
has_last_lvalue_type: bool

last_value_tag: TypeTag
last_value_custom: string
has_last_value_type: bool

struct_types: map[string]bool
var_types: map[string]VarType
fn_cursor_map: map[int]string
fn_typedefs: map[string]string
fn_var_typedefs: map[string]string

last_fn_typedef: string
has_last_fn_typedef: bool

output: strings.Builder
typedef_output: strings.Builder

init_compiler :: proc() {
	struct_types = make(map[string]bool)
	var_types = make(map[string]VarType)
	fn_cursor_map = make(map[int]string)
	fn_typedefs = make(map[string]string)
	fn_var_typedefs = make(map[string]string)
	strings.builder_init(&output)
	strings.builder_init(&typedef_output)
	counter = Counter{}
}

emit_c_escaped_string :: proc(out: ^strings.Builder, s: string) {
	fmt.sbprintf(out, "\"")
	for b in s {
		switch b {
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

is_function_typedef :: proc(type_name: string) -> bool {
	for _, v in fn_typedefs {
		if v == type_name {
			return true
		}
	}
	return false
}

emit_var_decl_default :: proc(out: ^strings.Builder, type_name: string, var_name: string, is_custom: bool) {
	if is_custom && !is_function_typedef(type_name) {
		fmt.sbprintf(out, "  %s %s = {{0}};\n", type_name, var_name)
	} else {
		fmt.sbprintf(out, "  %s %s = 0;\n", type_name, var_name)
	}
}

is_struct_type :: proc(type_name: string) -> bool {
	return struct_types[type_name]
}

register_struct_type :: proc(type_name: string) {
	if struct_types[type_name] {
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
	if lhs_tag == .bool || rhs_tag == .bool do return lhs_tag == rhs_tag
	if lhs_tag == .ptr || rhs_tag == .ptr do return lhs_tag == rhs_tag
	if type_tag_is_numeric(lhs_tag) && type_tag_is_numeric(rhs_tag) do return true
	return lhs_tag == rhs_tag
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

parse_fn_decl_args :: proc(l: ^lex.lexer, out: ^strings.Builder) -> bool {
	if !lex.get_token(l) do return true
	fmt.sbprintf(out, "(")
	for !(l.token.type == .punct && byte(l.token.intlit) == ')') {
		if l.token.type != .id {
			fmt.eprintfln(
				"%s:%d:%d expected argument name but got {}",
				l.token.file,
				l.token.row,
				l.token.col,
				l.token.type,
			)
			return true
		}

		arg_name := l.token.str
		if !lex.get_token(l) do return true
		if l.token.type != .punct || byte(l.token.intlit) != ':' {
			fmt.eprintfln(
				"%s:%d:%d expected ':' after argument name",
				l.token.file,
				l.token.row,
				l.token.col,
			)
			return true
		}

		if !lex.get_token(l) do return true
		if l.token.type != .id {
			fmt.eprintfln(
				"%s:%d:%d expected type after ':'",
				l.token.file,
				l.token.row,
				l.token.col,
			)
			return true
		}

		arg_type, vtype, ok := resolve_decl_type(l)
		if !ok {
			fmt.eprintfln(
				"%s:%d:%d unknown type (%s) in function arguments",
				l.token.file,
				l.token.row,
				l.token.col,
				l.token.str,
			)
			return true
		}

		fmt.sbprintf(out, "%s %s", arg_type, arg_name)
		var_types[arg_name] = vtype
		if vtype.tag == .custom {
			fn_var_typedefs[arg_name] = arg_type
		}

		if !lex.get_token(l) do return true
		if l.token.type == .punct && byte(l.token.intlit) == ',' {
			fmt.sbprintf(out, ", ")
			if !lex.get_token(l) do return true
		}
	}
	fmt.sbprintf(out, ")")
	return false
}

parse_struct_decl :: proc(l: ^lex.lexer) -> bool {
	if !lex.get_token(l) do return true
	if l.token.type != .id {
		fmt.eprintfln("%s:%d:%d expected struct name", l.token.file, l.token.row, l.token.col)
		return true
	}
	struct_name := l.token.str
	register_struct_type(struct_name)

	if !lex.get_token(l) do return true
	if l.token.type != .punct || byte(l.token.intlit) != '{' {
		fmt.eprintfln(
			"%s:%d:%d expected '{' after struct name",
			l.token.file,
			l.token.row,
			l.token.col,
		)
		return true
	}

	emit_source_line(&typedef_output, l)
	fmt.sbprintf(&typedef_output, "typedef struct {{\n")

	for lex.get_token(l) {
		if l.token.type == .punct && byte(l.token.intlit) == '}' {
			break
		}
		if l.token.type != .id {
			fmt.eprintfln(
				"%s:%d:%d expected field name in struct declaration",
				l.token.file,
				l.token.row,
				l.token.col,
			)
			return true
		}
		field_name := l.token.str

		if !lex.get_token(l) do return true
		if l.token.type != .punct || byte(l.token.intlit) != ':' {
			fmt.eprintfln(
				"%s:%d:%d expected ':' after struct field name",
				l.token.file,
				l.token.row,
				l.token.col,
			)
			return true
		}

		if !lex.get_token(l) do return true
		if l.token.type != .id {
			fmt.eprintfln("%s:%d:%d expected field type", l.token.file, l.token.row, l.token.col)
			return true
		}

		c_type, _, ok := resolve_decl_type(l)
		if !ok {
			fmt.eprintfln(
				"%s:%d:%d unknown type (%s) in struct field",
				l.token.file,
				l.token.row,
				l.token.col,
				l.token.str,
			)
			return true
		}
		fmt.sbprintf(&typedef_output, "  %s %s;\n", c_type, field_name)

		if !lex.get_token(l) do return true
		if l.token.type == .punct && byte(l.token.intlit) == ',' {
			continue
		}
		if l.token.type == .punct && byte(l.token.intlit) == '}' {
			break
		}
		fmt.eprintfln(
			"%s:%d:%d expected ',' or '}' after struct field declaration",
			l.token.file,
			l.token.row,
			l.token.col,
		)
		return true
	}

	if l.token.type != .punct || byte(l.token.intlit) != '}' {
		fmt.eprintfln(
			"%s:%d:%d expected '}' to close struct declaration",
			l.token.file,
			l.token.row,
			l.token.col,
		)
		return true
	}

	if !lex.get_token(l) do return true
	if l.token.type != .punct || byte(l.token.intlit) != ';' {
		fmt.eprintfln(
			"%s:%d:%d expected ';' after struct declaration",
			l.token.file,
			l.token.row,
			l.token.col,
		)
		return true
	}

	fmt.sbprintf(&typedef_output, "}} %s;\n", struct_name)
	return false
}

fn_pass :: proc(l: ^lex.lexer) -> bool {
	if l.token.type != .id {
		return false
	}

	switch get_keyword(l) {
	case .struct_:
		return parse_struct_decl(l)

	case .fn:
		cursor := int(l.cursor)
		if !lex.get_token(l) do return true

		fn_name := ""
		if l.token.type == .punct && byte(l.token.intlit) == '(' {
			fn_name = fmt.tprintf("anofunc_%d", counter.index)
			counter.index += 1
		} else if l.token.type == .id {
			fn_name = l.token.str
			if !lex.get_token(l) do return true
			if l.token.type != .punct || byte(l.token.intlit) != '(' {
				fmt.eprintfln(
					"%s:%d:%d expected '(' after function name",
					l.token.file,
					l.token.row,
					l.token.col,
				)
				return true
			}
		} else {
			fmt.eprintfln(
				"%s:%d:%d expected function name or '('",
				l.token.file,
				l.token.row,
				l.token.col,
			)
			return true
		}

		fn_cursor_map[cursor] = fn_name

		args_builder: strings.Builder
		strings.builder_init(&args_builder)
		if parse_fn_decl_args(l, &args_builder) {
			return true
		}
		args_sig := strings.to_string(args_builder)

		if !lex.get_token(l) do return true
		if l.token.type != .punct || byte(l.token.intlit) != ':' {
			fmt.eprintfln(
				"%s:%d:%d expected ':' after function arguments",
				l.token.file,
				l.token.row,
				l.token.col,
			)
			return true
		}

		if !lex.get_token(l) do return true
		if l.token.type != .id {
			fmt.eprintfln("%s:%d:%d expected return type", l.token.file, l.token.row, l.token.col)
			return true
		}

		ret_type, _, ok := resolve_decl_type(l)
		if !ok {
			fmt.eprintfln(
				"%s:%d:%d unknown return type (%s)",
				l.token.file,
				l.token.row,
				l.token.col,
				l.token.str,
			)
			return true
		}

		emit_source_line(&output, l)
		fmt.sbprintf(&output, "%s %s%s {{\n", ret_type, fn_name, args_sig)

		fn_typedef := fmt.tprintf("%s_t", fn_name)
		fn_typedefs[fn_name] = fn_typedef
		emit_source_line(&typedef_output, l)
		fmt.sbprintf(&typedef_output, "typedef %s (*%s)%s;\n", ret_type, fn_typedef, args_sig)

		if !lex.get_token(l) do return true
		if main_pass(l, false) {
			return true
		}

		fmt.sbprintf(&output, "  return 0;\n}}\n\n")
   	case .none:
  	case .let:
  	case .while:
  	case .if_:


	}

	return false
}

prepass :: proc(l: ^lex.lexer) -> bool {
	for lex.get_token(l) {
		if fn_pass(l) {
			return true
		}
	}
	reset_lexer(l)
	return false
}

main_pass :: proc(l: ^lex.lexer, skip: bool) -> bool {
	if !skip && l.token.type != .either_end_or_failure {
		emit_source_line(&output, l)
	}

	switch l.token.type {
	case .intlit:
		if !skip {
			t := TypeTag.i64
			if counter.type_tag == .i32 ||
			   counter.type_tag == .i64 ||
			   counter.type_tag == .f32 ||
			   counter.type_tag == .f64 ||
			   counter.type_tag == .u8 ||
			   counter.type_tag == .u16 ||
			   counter.type_tag == .i8 ||
			   counter.type_tag == .i16 ||
			   counter.type_tag == .bool {
				t = counter.type_tag
			}
			fmt.sbprintf(
				&output,
				"  %s t%d = %d;\n",
				type_tag_to_c(t),
				counter.index,
				l.token.intlit,
			)
			counter.index += 1
			last_value_tag = t
			last_value_custom = ""
			has_last_value_type = true
			counter.type_tag = t
		}
	case .floatlit:
		if !skip {
			t := TypeTag.f64
			if counter.type_tag == .f32 || counter.type_tag == .f64 {
				t = counter.type_tag
			}
			fmt.sbprintf(
				&output,
				"  %s t%d = %f;\n",
				type_tag_to_c(t),
				counter.index,
				l.token.floatlit,
			)
			counter.index += 1
			last_value_tag = t
			last_value_custom = ""
			has_last_value_type = true
			counter.type_tag = t
		}
	case .punct, .eq, .plusplus, .minusminus:
		c_idx := counter.index - 1
		switch get_punct(l) {
		case .assign:
			for lex.get_token(l) {
				if main_pass(l, false) {
					return true
				}
				if l.token.type == .punct && byte(l.token.intlit) == ';' {
					break
				}
			}

			if has_last_lvalue && has_last_lvalue_type && has_last_value_type {
				if !type_is_assignable(
					last_lvalue_tag,
					last_lvalue_custom,
					last_value_tag,
					last_value_custom,
				) {
					fmt.eprintfln(
						"%s:%d:%d type mismatch in assignment to %s",
						l.token.file,
						l.token.row,
						l.token.col,
						last_lvalue,
					)
					return true
				}
			}

			if !skip && has_last_lvalue {
				fmt.sbprintf(&output, "  %s = t%d;\n", last_lvalue, counter.index - 1)
			}

		case .add:
			lhs_tag := counter.type_tag
			if !lex.get_token(l) do return true
			if main_pass(l, false) do return true
			rhs_tag := last_value_tag
			if !type_tag_is_numeric(lhs_tag) || !type_tag_is_numeric(rhs_tag) {
				fmt.eprintfln(
					"%s:%d:%d '+' expects numeric operands",
					l.token.file,
					l.token.row,
					l.token.col,
				)
				return true
			}
			res_tag := join_numeric_types(lhs_tag, rhs_tag)
			if !skip {
				fmt.sbprintf(
					&output,
					"  %s t%d = t%d + t%d;\n",
					type_tag_to_c(res_tag),
					counter.index,
					c_idx,
					counter.index - 1,
				)
			}
			counter.index += 1
			counter.type_tag = res_tag
			last_value_tag = res_tag
			last_value_custom = ""
			has_last_value_type = true

		case .sub:
			lhs_tag := counter.type_tag
			if !lex.get_token(l) do return true
			if main_pass(l, false) do return true
			rhs_tag := last_value_tag
			if !type_tag_is_numeric(lhs_tag) || !type_tag_is_numeric(rhs_tag) {
				fmt.eprintfln(
					"%s:%d:%d '-' expects numeric operands",
					l.token.file,
					l.token.row,
					l.token.col,
				)
				return true
			}
			res_tag := join_numeric_types(lhs_tag, rhs_tag)
			if !skip {
				fmt.sbprintf(
					&output,
					"  %s t%d = t%d - t%d;\n",
					type_tag_to_c(res_tag),
					counter.index,
					c_idx,
					counter.index - 1,
				)
			}
			counter.index += 1
			counter.type_tag = res_tag
			last_value_tag = res_tag
			last_value_custom = ""
			has_last_value_type = true

		case .mod:
			lhs_tag := counter.type_tag
			if !lex.get_token(l) do return true
			if main_pass(l, false) do return true
			rhs_tag := last_value_tag
			if !type_tag_is_integer(lhs_tag) || !type_tag_is_integer(rhs_tag) {
				fmt.eprintfln(
					"%s:%d:%d '%%' expects integer operands",
					l.token.file,
					l.token.row,
					l.token.col,
				)
				return true
			}
			res_tag := join_numeric_types(lhs_tag, rhs_tag)
			if !skip {
				fmt.sbprintf(
					&output,
					"  %s t%d = t%d %% t%d;\n",
					type_tag_to_c(res_tag),
					counter.index,
					c_idx,
					counter.index - 1,
				)
			}
			counter.index += 1
			counter.type_tag = res_tag
			last_value_tag = res_tag
			last_value_custom = ""
			has_last_value_type = true

		case .mult:
			lhs_tag := counter.type_tag
			if !lex.get_token(l) do return true
			if main_pass(l, false) do return true
			rhs_tag := last_value_tag
			if !type_tag_is_numeric(lhs_tag) || !type_tag_is_numeric(rhs_tag) {
				fmt.eprintfln(
					"%s:%d:%d '*' expects numeric operands",
					l.token.file,
					l.token.row,
					l.token.col,
				)
				return true
			}
			res_tag := join_numeric_types(lhs_tag, rhs_tag)
			if !skip {
				fmt.sbprintf(
					&output,
					"  %s t%d = t%d * t%d;\n",
					type_tag_to_c(res_tag),
					counter.index,
					c_idx,
					counter.index - 1,
				)
			}
			counter.index += 1
			counter.type_tag = res_tag
			last_value_tag = res_tag
			last_value_custom = ""
			has_last_value_type = true

		case .div:
			lhs_tag := counter.type_tag
			if !lex.get_token(l) do return true
			if main_pass(l, false) do return true
			rhs_tag := last_value_tag
			if !type_tag_is_numeric(lhs_tag) || !type_tag_is_numeric(rhs_tag) {
				fmt.eprintfln(
					"%s:%d:%d '/' expects numeric operands",
					l.token.file,
					l.token.row,
					l.token.col,
				)
				return true
			}
			res_tag := join_numeric_types(lhs_tag, rhs_tag)
			if !skip {
				fmt.sbprintf(
					&output,
					"  %s t%d = t%d / t%d;\n",
					type_tag_to_c(res_tag),
					counter.index,
					c_idx,
					counter.index - 1,
				)
			}
			counter.index += 1
			counter.type_tag = res_tag
			last_value_tag = res_tag
			last_value_custom = ""
			has_last_value_type = true

		case .eq:
			lhs_tag := counter.type_tag
			if !lex.get_token(l) do return true
			if main_pass(l, false) do return true
			rhs_tag := last_value_tag
			if !type_is_assignable(lhs_tag, "", rhs_tag, "") &&
			   !type_is_assignable(rhs_tag, "", lhs_tag, "") {
				fmt.eprintfln(
					"%s:%d:%d '==' expects compatible operand types",
					l.token.file,
					l.token.row,
					l.token.col,
				)
				return true
			}
			if !skip {
				fmt.sbprintf(
					&output,
					"  int32_t t%d = t%d == t%d;\n",
					counter.index,
					c_idx,
					counter.index - 1,
				)
			}
			counter.index += 1
			counter.type_tag = .bool
			last_value_tag = .bool
			last_value_custom = ""
			has_last_value_type = true

		case .pp:
			if !skip && has_last_lvalue {
				fmt.sbprintf(&output, "  ++%s;\n", last_lvalue)
			}
		case .mm:
			if !skip && has_last_lvalue {
				fmt.sbprintf(&output, "  --%s;\n", last_lvalue)
			}
		case .less:
			lhs_tag := counter.type_tag
			if !lex.get_token(l) do return true
			if main_pass(l, false) do return true
			rhs_tag := last_value_tag
			if !type_is_assignable(lhs_tag, "", rhs_tag, "") &&
			   !type_is_assignable(rhs_tag, "", lhs_tag, "") {
				fmt.eprintfln(
					"%s:%d:%d '<' expects compatible operand types",
					l.token.file,
					l.token.row,
					l.token.col,
				)
				return true
			}
			if !skip {
				fmt.sbprintf(
					&output,
					"  int32_t t%d = t%d < t%d;\n",
					counter.index,
					c_idx,
					counter.index - 1,
				)
			}
			counter.index += 1
			counter.type_tag = .bool
			last_value_tag = .bool
			last_value_custom = ""
			has_last_value_type = true

		case .greater:
			lhs_tag := counter.type_tag
			if !lex.get_token(l) do return true
			if main_pass(l, false) do return true
			rhs_tag := last_value_tag
			if !type_is_assignable(lhs_tag, "", rhs_tag, "") &&
			   !type_is_assignable(rhs_tag, "", lhs_tag, "") {
				fmt.eprintfln(
					"%s:%d:%d '>' expects compatible operand types",
					l.token.file,
					l.token.row,
					l.token.col,
				)
				return true
			}
			if !skip {
				fmt.sbprintf(
					&output,
					"  int32_t t%d = t%d > t%d;\n",
					counter.index,
					c_idx,
					counter.index - 1,
				)
			}
			counter.index += 1
			counter.type_tag = .bool
			last_value_tag = .bool
			last_value_custom = ""
			has_last_value_type = true

		case .error:
			return true
		case .none:
		}

	case .id:
		switch get_keyword(l) {
		case .let:
			if !lex.get_token(l) do return true
			if l.token.type != .id {
				fmt.eprintfln(
					"%s:%d:%d expected variable name",
					l.token.file,
					l.token.row,
					l.token.col,
				)
				return true
			}
			var_name := l.token.str

			if !lex.get_token(l) do return true
			if l.token.type != .punct || byte(l.token.intlit) != ':' {
				fmt.eprintfln(
					"%s:%d:%d expected ':' after variable name",
					l.token.file,
					l.token.row,
					l.token.col,
				)
				return true
			}

			if !lex.get_token(l) do return true
			if l.token.type != .id {
				fmt.eprintfln(
					"%s:%d:%d expected type in variable declaration",
					l.token.file,
					l.token.row,
					l.token.col,
				)
				return true
			}
			decl_type, decl_vtype, ok := resolve_decl_type(l)
			if !ok {
				fmt.eprintfln(
					"%s:%d:%d unknown type (%s) in variable declaration",
					l.token.file,
					l.token.row,
					l.token.col,
					l.token.str,
				)
				return true
			}
			var_types[var_name] = decl_vtype
			if decl_vtype.tag == .custom {
				fn_var_typedefs[var_name] = decl_type
			}

			decl_expected_tag := decl_vtype.tag
			decl_expected_custom := ""
			if decl_vtype.tag == .custom {
				decl_expected_custom = decl_vtype.custom
			}

			inferred_decl_type := ""

			if !lex.get_token(l) do return true
			if l.token.type == .punct && byte(l.token.intlit) == '=' {
				first_token := true
				has_last_fn_typedef = false
				if decl_vtype.tag != .custom {
					counter.type_tag = decl_vtype.tag
				}

				for lex.get_token(l) {
					if first_token && l.token.type == .id && get_keyword(l) == .none {
						if rhs_typedef, ok := fn_var_typedefs[l.token.str]; ok {
							inferred_decl_type = rhs_typedef
						}
					}
					if main_pass(l, false) {
						return true
					}
					if first_token && has_last_fn_typedef {
						inferred_decl_type = last_fn_typedef
					}
					first_token = false
					if l.token.type == .punct && byte(l.token.intlit) == ';' {
						break
					}
				}

				final_decl_tag := decl_expected_tag
				final_decl_custom := decl_expected_custom
				if inferred_decl_type != "" {
					final_decl_tag = .custom
					final_decl_custom = inferred_decl_type
				}
				if has_last_value_type &&
				   !type_is_assignable(
						   final_decl_tag,
						   final_decl_custom,
						   last_value_tag,
						   last_value_custom,
					   ) {
					fmt.eprintfln(
						"%s:%d:%d type mismatch in initializer for %s",
						l.token.file,
						l.token.row,
						l.token.col,
						var_name,
					)
					return true
				}

				if !skip {
					final_decl_type := decl_type
					if inferred_decl_type != "" {
						final_decl_type = inferred_decl_type
					}
					emit_source_line(&output, l)
					emit_var_decl_default(&output, final_decl_type, var_name, final_decl_tag == .custom)
					emit_source_line(&output, l)
					fmt.sbprintf(&output, "  %s = t%d;\n", var_name, counter.index - 1)
				}
				if inferred_decl_type != "" {
					fn_var_typedefs[var_name] = inferred_decl_type
					var_types[var_name] = VarType{.custom, inferred_decl_type}
				}
			} else if !skip {
				emit_source_line(&output, l)
				emit_var_decl_default(&output, decl_type, var_name, decl_expected_tag == .custom)
			}

			has_last_lvalue = true
			last_lvalue = var_name
			has_last_lvalue_type = true
			if inferred_decl_type != "" {
				last_lvalue_tag = .custom
				last_lvalue_custom = inferred_decl_type
			} else {
				last_lvalue_tag = decl_expected_tag
				last_lvalue_custom = decl_expected_custom
			}

		case .if_:
			if !lex.get_token(l) do return true
			if main_pass(l, false) do return true

			if !skip {
				fmt.sbprintf(&output, "  if (t%d) {{\n", counter.index - 1)
			}

			if main_pass(l, false) do return true
			if !skip {
				fmt.sbprintf(&output, "  }}\n")
			}

			if l.token.type == .punct && byte(l.token.intlit) == ')' {
				if !lex.get_token(l) do return true
			}
			if l.token.type == .punct && byte(l.token.intlit) == ';' {
				if !lex.get_token(l) do return true
			}

			if l.token.type == .id && l.token.str == "else" {
				if !lex.get_token(l) do return true
				if !skip {
					fmt.sbprintf(&output, "  else {{\n")
				}
				if main_pass(l, false) do return true
				if !skip {
					fmt.sbprintf(&output, "  }}\n")
				}
			}

		case .while:
			if !skip {
				fmt.sbprintf(&output, "  while (1) {{\n")
			}
			if !lex.get_token(l) do return true
			if main_pass(l, false) do return true
			if !skip {
				fmt.sbprintf(&output, "  if (!t%d) break;\n", counter.index - 1)
			}
			if main_pass(l, false) do return true
			if !skip {
				fmt.sbprintf(&output, "  }}\n")
			}

		case .fn:
			if fn_name, ok := fn_cursor_map[int(l.cursor)]; ok {
				fn_typedef := fmt.tprintf("%s_t", fn_name)
				last_fn_typedef = fn_typedef
				has_last_fn_typedef = true
				if !skip {
					fmt.sbprintf(&output, "  %s t%d = &%s;\n", fn_typedef, counter.index, fn_name)
					counter.index += 1
				}
				counter.type_tag = .invalid
				last_value_tag = .custom
				last_value_custom = fn_typedef
				has_last_value_type = true

				brace_depth := 0
				seen_body := false
				for lex.get_token(l) {
					if l.token.type != .punct do continue
					ch := byte(l.token.intlit)
					if ch == '{' {
						seen_body = true
						brace_depth += 1
					} else if ch == '}' {
						if brace_depth > 0 do brace_depth -= 1
						if seen_body && brace_depth == 0 do break
					}
				}
				return false
			}
			fmt.eprintfln(
				"%s:%d:%d this function has no cursor mapping",
				l.token.file,
				l.token.row,
				l.token.col,
			)
			return true

		case .struct_:
			brace_depth := 0
			seen_body := false
			for lex.get_token(l) {
				if l.token.type != .punct do continue
				ch := byte(l.token.intlit)
				if ch == '{' {
					seen_body = true
					brace_depth += 1
				} else if ch == '}' {
					if brace_depth > 0 do brace_depth -= 1
					if seen_body && brace_depth == 0 do break
				}
			}
			if !lex.get_token(l) do return true
			if l.token.type != .punct || byte(l.token.intlit) != ';' {
				fmt.eprintfln(
					"%s:%d:%d expected ';' after struct declaration",
					l.token.file,
					l.token.row,
					l.token.col,
				)
				return true
			}

		case .none:
			temp := l.token.str
			if temp == "true" || temp == "false" {
				if !skip {
					fmt.sbprintf(&output, "  bool t%d = %s;\n", counter.index, temp)
					counter.index += 1
				}
				counter.type_tag = .bool
				last_value_tag = .bool
				last_value_custom = ""
				has_last_value_type = true
				return false
			}

			peek_tok := l^
			if lex.get_token(&peek_tok) &&
			   peek_tok.token.type == .punct &&
			   byte(peek_tok.token.intlit) == '(' {
				args_builder: strings.Builder
				strings.builder_init(&args_builder)
				arg_count := 0
				var_typedef, has_var_typedef := fn_var_typedefs[temp]
				_, call_via_var := var_types[temp]

				if lex.get_token(l) && l.token.type == .punct && byte(l.token.intlit) == '(' {
					peek2 := l^
					if lex.get_token(&peek2) &&
					   !(peek2.token.type == .punct && byte(peek2.token.intlit) == ')') {
						quit := false
						for !quit && lex.get_token(l) {
							if l.token.type == .punct && byte(l.token.intlit) == ')' {
								quit = true
							}
							if main_pass(l, false) {
								return true
							}
							if l.token.type == .punct {
								ch := byte(l.token.intlit)
								if ch == ',' || ch == ')' {
									if arg_count > 0 {
										fmt.sbprintf(&args_builder, ", ")
									}
									fmt.sbprintf(&args_builder, "t%d", counter.index - 1)
									arg_count += 1
								}
							}
						}
					}
				}

				if !skip {
					if call_via_var && has_var_typedef {
						fmt.sbprintf(&output, "  int64_t t%d = %s(", counter.index, temp)
					} else if call_via_var {
						fmt.sbprintf(
							&output,
							"  int64_t t%d = ((int64_t (*)())(uintptr_t)%s)(",
							counter.index,
							temp,
						)
					} else {
						fmt.sbprintf(&output, "  int64_t t%d = %s(", counter.index, temp)
					}
					fmt.sbprintf(&output, "%s", strings.to_string(args_builder))
					fmt.sbprintf(&output, ");\n")
				}
				counter.index += 1
				counter.type_tag = .i64
				last_value_tag = .i64
				last_value_custom = ""
				has_last_value_type = true
				return false
			}

			vtype, ok := var_types[temp]
			if !ok {
				fmt.eprintfln(
					"%s:%d:%d id (%s) is unknown",
					l.token.file,
					l.token.row,
					l.token.col,
					temp,
				)
				return true
			}

			has_last_lvalue = true
			last_lvalue = temp
			has_last_lvalue_type = true
			if vtype.tag == .custom {
				last_lvalue_tag = .custom
				last_lvalue_custom = vtype.custom
				last_value_tag = .custom
				last_value_custom = vtype.custom
			} else {
				last_lvalue_tag = vtype.tag
				last_lvalue_custom = ""
				last_value_tag = vtype.tag
				last_value_custom = ""
			}
			peek_member := l^
			if lex.get_token(&peek_member) &&
			   peek_member.token.type == .punct &&
			   byte(peek_member.token.intlit) == '.' {
				member_expr := temp
				for lex.get_token(l) {
					if l.token.type != .punct || byte(l.token.intlit) != '.' {
						fmt.eprintfln(
							"%s:%d:%d expected '.' for member access",
							l.token.file,
							l.token.row,
							l.token.col,
						)
						return true
					}
					if !lex.get_token(l) do return true
					if l.token.type != .id {
						fmt.eprintfln(
							"%s:%d:%d expected field name after '.'",
							l.token.file,
							l.token.row,
							l.token.col,
						)
						return true
					}
					member_expr = strings.concatenate({member_expr, ".", l.token.str})
					peek_next := l^
					if !(lex.get_token(&peek_next) &&
						   peek_next.token.type == .punct &&
						   byte(peek_next.token.intlit) == '.') {
						break
					}
				}

				peek_after_member := l^
				lvalue_only := false
				if lex.get_token(&peek_after_member) {
					if peek_after_member.token.type == .punct &&
					   byte(peek_after_member.token.intlit) == '=' {
						lvalue_only = true
					} else if peek_after_member.token.type == .plusplus ||
					          peek_after_member.token.type == .minusminus {
						lvalue_only = true
					}
				}

				if !skip && !lvalue_only {
					fmt.sbprintf(&output, "  int64_t t%d = %s;\n", counter.index, member_expr)
				}
				if !lvalue_only {
					counter.index += 1
					counter.type_tag = .i64
					last_value_tag = .i64
					last_value_custom = ""
					has_last_value_type = true
				} else {
					has_last_value_type = false
				}
				has_last_lvalue = true
				last_lvalue = member_expr
				has_last_lvalue_type = false
			} else {
				peek_after_id := l^
				lvalue_only := false
				if lex.get_token(&peek_after_id) {
					if peek_after_id.token.type == .punct &&
					   byte(peek_after_id.token.intlit) == '=' {
						lvalue_only = true
					} else if peek_after_id.token.type == .plusplus ||
					          peek_after_id.token.type == .minusminus {
						lvalue_only = true
					}
				}

				if !skip && !lvalue_only {
					if vtype.tag == .custom {
						fmt.sbprintf(&output, "  %s t%d = %s;\n", vtype.custom, counter.index, temp)
					} else {
						fmt.sbprintf(
							&output,
							"  %s t%d = %s;\n",
							type_tag_to_c(vtype.tag),
							counter.index,
							temp,
						)
					}
				}
				if !lvalue_only {
					counter.index += 1
					counter.type_tag = vtype.tag
					has_last_value_type = true
				} else {
					has_last_value_type = false
				}
			}

		}

	case .dqstring:
		if !skip {
			fmt.sbprintf(&output, "  const char *t%d = ", counter.index)
			emit_c_escaped_string(&output, l.token.str)
			fmt.sbprintf(&output, ";\n")
			counter.index += 1
		}
		counter.type_tag = .ptr
		last_value_tag = .ptr
		last_value_custom = ""
		has_last_value_type = true

	case .either_end_or_failure:
		return true
	case .none:
	case .charlit:
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

	return false
}
