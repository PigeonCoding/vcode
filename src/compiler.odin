package vcode

import lex "../libs/lexer"
import "core:fmt"
import "core:strings"

L_Custom :: enum {
	none,
	fn,
	ret,
}

base_type_to_qbe :: proc(s: string) -> qbe_types {
	switch s {
	case "void":
		return .none
	case "i32":
		return .I32
	case "i64":
		return .I64
	case "f32":
		return .F32
	case "f64":
		return .F64
	case:
		fmt.eprintfln("unkown base type (%s)", s)
		return .none
	}
	return .none
}

qbe_types :: enum {
	none,
	I32,
	I64,
	F32,
	F64,
}

qbe_types_str := []string{"", "w", "l", "s", "d"}

lexer_custom :: proc(l: ^lex.lexer, lc: lex.lexer) {
	c := lc
	{
		found := false
		i := 0

		// function decl
		found = true
		if c.token.type != .id {
			found = false
		}
		if t, ok := lex.peek_token(l); ok && found {
			if !(t.type == .punct && t.intlit == ':') {
				found = false
			}
		} else if found {
			found = false
		}
		if t, ok := lex.peek_token(l, 2); ok && found {
			if !(t.type == .punct && t.intlit == ':') {
				found = false
			}
		} else if found {
			found = false
		}
		if t, ok := lex.peek_token(l, 3); ok && found {
			if !(t.type == .id && t.str == "fn") {
				found = false
			}
		} else if found {
			found = false
		}
		i = 4
		if found {
			end: for {
				t, ok := lex.peek_token(l, i)
				if !ok {
					found = false
					break end
				}
				if t.type == .punct && t.intlit == ')' {
					break end
				}
				i += 1
			}
		}
		i += 1
		if t, ok := lex.peek_token(l, i); ok && found {
			if !(t.type == .punct && t.intlit == ':') {
				found = false
			}
		} else if found {
			found = false
		}
		i += 1
		n, ok := lex.peek_token(l, i)
		if !ok do found = false

		if found {
			l.token.type = .custom
			l.token.custom_data = auto_cast L_Custom.fn
			l.token.str = strings.concatenate([]string{n.str, " ", l.token.str})
			return
		}
	}

	{
		// return
		if c.token.type == .id && c.token.str == "return" {
			l.token.type = .custom
			l.token.custom_data = auto_cast L_Custom.ret
			return
		}
	}
}


compile_to_qbe :: proc(l: ^lex.lexer, out: ^strings.Builder) -> bool {
	#partial switch l.token.type {
	case .custom:
		#partial switch cast(L_Custom)l.token.custom_data {
		case .ret:
			if !lex.get_token(l) do return false
			assert(l.token.type == .intlit, "have not implemented returning non int const values")
			fmt.sbprintf(out, "  ret %d\n", l.token.intlit)
			if !lex.get_token(l) do return false
			return true

		case .fn:
			deconstruct := strings.split(l.token.str, " ")
			assert(
				len(deconstruct) == 2,
				"when the fn was found it did not find the name and type for some reason",
			)
			type := deconstruct[0]

			name := deconstruct[1]
			fmt.sbprintf(
				out,
				"export function %s $%s(",
				qbe_types_str[base_type_to_qbe(type)],
				name,
			)
			s := len(out.buf)

			if !lex.get_token(l) do return false
			if !lex.get_token(l) do return false
			if !lex.get_token(l) do return false
			if !lex.get_token(l) do return false
			if !lex.get_token(l) do return false
			assert(l.token.intlit == ')', "heven't implemented function argument parsing")
			if !lex.get_token(l) do return false
			if !lex.get_token(l) do return false
			if !lex.get_token(l) do return false
			fmt.sbprintf(out, ")\n")
			fmt.sbprintf(
				out,
				"function %s $%s() {{\n",
				qbe_types_str[base_type_to_qbe(type)],
				name,
			)


			if !compile_to_qbe(l, out) do return false

			fmt.sbprintf(out, "}\n")
			return true
		case:
			fmt.eprintfln("unknown custom token type ({})", cast(L_Custom)l.token.custom_data)
			return false
		}
	case .punct:
		if l.token.intlit == '{' {
			if !lex.get_token(l) do return false
			for !(l.token.type == .punct && l.token.intlit == '}') {
				if !compile_to_qbe(l, out) do return false
			}
		}
		return true

	case:
		fmt.eprintfln("unknown token type ({})", l.token.type)
		return false

	}


	return true
}
