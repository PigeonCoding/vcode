package vcode

import lex "../libs/lexer"
import "core:fmt"
import "core:strings"

L_Custom :: enum (i64) {
	none,
	fn,
}

lexer_custom :: proc(l: ^lex.lexer) {
	found := false

	// function decl
	found = true
	if l.token.type != .id {
		found = false
	}
	if t, ok := lex.peek_token(l); ok && found {
		if !(t.type == .punct && t.intlit == ':') {
			found = false
		}
	}
	if t, ok := lex.peek_token(l, 2); ok && found {
		if !(t.type == .punct && t.intlit == ':') {
			found = false
		}
	}
	if t, ok := lex.peek_token(l, 3); ok && found {
		if !(t.type == .id && t.str == "fn") {
			found = false
		}
	}

	if found {
		l.token.type = .custom
		l.token.intlit = auto_cast L_Custom.fn
		// fmt.println("fn")
		return
	}


}


compile_to_qbe :: proc(l: ^lex.lexer, out: ^strings.Builder) -> bool {

	#partial switch l.token.type {
	case .custom:
		#partial switch cast(L_Custom)l.token.intlit {
		case:
			fmt.eprintfln("unknown custom token type ({})", cast(L_Custom)l.token.intlit)
			return false
		}
	case:
		fmt.eprintfln("unknown token type ({})", l.token.type)
		return false
	}


	return true
}
