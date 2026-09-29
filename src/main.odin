package vcode

import flag "../libs/flags"
import lex "../libs/lexer"
import "core:fmt"
import "core:os"
import "core:strings"

usage :: proc(program: string, cont: ^flag.flag_container) {
	fmt.eprintfln("Usage: %s [OPTIONS] file.vc", program)
	fmt.eprintln("OPTIONS:")
	flag.print_usage(cont)
}

main :: proc() {
	cont: flag.flag_container
	cont.flags_map = make(map[string]^flag.flag_t)
	cont.skip_pogram_name = true

	flag.add_flag(&cont, "help", false, "Print this help to stdout and exit with 0")
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

	init_aster()

	l: lex.lexer

	for file in cont.remaining {
		init_aster()
		lexed: [dynamic]lex.token
		tree: ast_tree
		l = lex.init_lexer(file)
		for lex.get_token(&l) {
			append(&lexed, l.token)
		}

		// fmt.println(lexed[:])
		get_asted(lexed[:], &tree)
		fmt.println(tree)
		print_tree(&tree)
	}

}
