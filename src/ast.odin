package vcode

import lex "../libs/lexer"
import "core:fmt"
import "core:strings"

Node_t :: enum (u8) {
	empty,
	id,
	op,
}

Ops :: enum {
	none,
	assign,
	plus,
	minus,
}

node :: struct {
	type:  Node_t,
	val:   uintptr,
	L:     uint,
	R:     uint,
	order: int,
}

ast_tree :: struct {
	tree:  [dynamic]node,
	atoms: int,
}

temp_arena: [dynamic]node
current: uint = 0

init_aster :: proc() {
	current = 0
	clear(&temp_arena)
}

clean_aster :: proc() {
	current = 0
	clear(&temp_arena)
}

op_prec :: proc(o: Ops) -> int {
	#partial switch o {
	case .assign:
		return 1
	case .plus:
		return 10
	case .minus:
		return 20
	// case .star, .slash:
	// 	return 20
	}
	return 0
}

op_right_assoc :: proc(o: Ops) -> bool {
	return o == .assign
}

get_asted :: proc(lexes: []lex.token, tree: ^ast_tree) {
	out: [dynamic]node
	defer delete(out)
	op_stack: [dynamic]node
	defer delete(op_stack)

	for &l in lexes {
		#partial switch l.type {
		case .id:
			append(&out, node{type = .id, val = auto_cast &l.str})

		case .assign, .plus, .minus:
			//, .star, .slash:
			op: Ops
			#partial switch l.type {
			case .assign:
				op = .assign
			case .plus:
				op = .plus
			case .minus:
				op = .minus
			// case .star:
			// 	op = .star
			// case .slash:
			// 	op = .slash
			case:
				continue
			}

			np := op_prec(op)
			for len(op_stack) > 0 {
				top := op_stack[len(op_stack) - 1]
				tp := op_prec(cast(Ops)top.val)
				if tp > np || (tp == np && !op_right_assoc(op)) {
					append(&out, top)
					pop(&op_stack)
					// resize(&op_stack, len(op_stack) - 1)
				} else {
					break
				}
			}
			append(&op_stack, node{type = .op, val = auto_cast op})
		}
	}

	// Drain remaining operators.
	for len(op_stack) > 0 {
		append(&out, op_stack[len(op_stack) - 1])
		pop(&op_stack)
		// resize(&op_stack, len(op_stack) - 1)
	}

	clear(&tree.tree)
	for n in out do append(&tree.tree, n)
	tree.atoms = -1
}

op_name :: proc(o: Ops) -> string {
	#partial switch o {
	case .assign:
		return "="
	case .plus:
		return "+"
	case .minus:
		return "-"
	// case .star:   return "*"
	// case .slash:  return "/"
	}
	return "?"
}

Print_Node :: struct {
	name: string,
	lhs:  ^Print_Node,
	rhs:  ^Print_Node,
}

build_print_tree :: proc(tree: ^ast_tree) -> ^Print_Node {
	stack: [dynamic]^Print_Node

	for n in tree.tree {
		leaf := new(Print_Node)
		#partial switch n.type {
		case .id:
			// Adjust cast to match how you stored l.str.
			// If l.str is `string`, `(^string)(n.val)^` is correct.
			leaf.name = (^string)(n.val)^
			append(&stack, leaf)
		case .op:
			if len(stack) < 2 {
				fmt.eprintln("malformed tree: operator with <2 operands")
				return nil
			}
			rhs := stack[len(stack) - 1]; resize(&stack, len(stack) - 1)
			lhs := stack[len(stack) - 1]; resize(&stack, len(stack) - 1)
			leaf.name = op_name(cast(Ops)n.val)
			leaf.lhs = lhs
			leaf.rhs = rhs
			append(&stack, leaf)
		}
	}

	if len(stack) != 1 {
		fmt.eprintln("malformed tree: leftover nodes")
		return nil
	}
	return stack[0]
}

print_tree_node :: proc(n: ^Print_Node, prefix: string, is_tail: bool, is_root: bool) {
	if n == nil do return

	if is_root {
		fmt.println(n.name)
	} else {
		connector := is_tail ? "└── " : "├── "
		fmt.print(prefix)
		fmt.print(connector)
		fmt.println(n.name)
	}

	// Build child prefix
	child_prefix: string
	if is_root {
		child_prefix = ""
	} else {
		// 4 chars wide to match "├── " / "└── "
		child_prefix = strings.concatenate([]string{prefix, is_tail ? "    " : "│   "})
	}

	// Count children so we can mark the last one
	children: [dynamic]^Print_Node
	if n.lhs != nil do append(&children, n.lhs)
	if n.rhs != nil do append(&children, n.rhs)

	for child, i in children {
		is_last := i == len(children) - 1
		print_tree_node(child, child_prefix, is_last, false)
	}
}
print_tree :: proc(tree: ^ast_tree) {
	root := build_print_tree(tree)
	if root == nil do return
	print_tree_node(root, "", false, true)
}
