// package qbe — Odin bindings for the vendored QBE backend (libs/qbe, v1.3).
//
// QBE is compiled as a static library (libqbe.a, see Makefile.lib and
// qbe_lib.h) and linked directly, so vcode can emit QBE IL and compile it
// to assembly in-process instead of shelling out to a `qbe` binary.
//
// Build the library first (wired into `odin run ./builder`, or manually):
//   make -C libs/qbe -f Makefile.lib libqbe.a
//
// NOTE: like the `qbe` CLI, malformed IL aborts the process — QBE's
// err()/die() call exit(). Only pass IL your own code generator produced.
// Sequential calls in one process are fine.
package qbe

import "core:c"
import "core:strings"

// Static library built from the vendored sources (relative to this file's
// directory). MSVC on Windows cannot link .a files; a .lib build is future
// work — on Windows keep shelling out to a qbe binary for now.
foreign import libqbe "./libqbe.a"

// Known backend targets (qbe -t). "" selects the build default.
TARGET_AMD64_SYSV  :: "amd64_sysv"
TARGET_AMD64_APPLE :: "amd64_apple"
TARGET_AMD64_WIN   :: "amd64_win"
TARGET_ARM64       :: "arm64"
TARGET_ARM64_APPLE :: "arm64_apple"
TARGET_RV64        :: "rv64"

Error :: enum c.int {
	None           = 0, // assembly written to asm_path
	Io             = 1, // cannot open ssa_path / asm_path
	Unknown_Target = 2, // unknown target name
}

@(default_calling_convention = "c")
foreign libqbe {
	@(link_name = "qbe_compile_file")          _compile_file          :: proc(ssa_path, asm_path, target: cstring) -> Error ---
	@(link_name = "qbe_compile_text")          _compile_text          :: proc(ssa_text, asm_path, target: cstring) -> Error ---
	@(link_name = "qbe_compile_text_to_memory") _compile_to_memory    :: proc(ssa_text, target: cstring, out_asm: ^[^]u8, out_len: ^c.size_t) -> Error ---
	@(link_name = "qbe_free_string")           _free_string           :: proc(s: [^]u8) ---
	@(link_name = "qbe_default_target")        _default_target        :: proc() -> cstring ---
	@(link_name = "qbe_set_debug")             _set_debug             :: proc(flags: cstring) ---
}

// compile_file compiles the QBE IL file at ssa_path, writing assembly to
// asm_path. target is one of the TARGET_* names, or "" for the default.
compile_file :: proc(ssa_path, asm_path: string, target := "") -> Error {
	s := strings.clone_to_cstring(ssa_path, context.temp_allocator)
	o := strings.clone_to_cstring(asm_path, context.temp_allocator)
	t := strings.clone_to_cstring(target, context.temp_allocator)
	return _compile_file(s, o, t)
}

// compile_text is compile_file for IL held in memory (e.g. just emitted by
// vcode's code generator).
compile_text :: proc(ssa_src: string, asm_path: string, target := "") -> Error {
	s := strings.clone_to_cstring(ssa_src, context.temp_allocator)
	o := strings.clone_to_cstring(asm_path, context.temp_allocator)
	t := strings.clone_to_cstring(target, context.temp_allocator)
	return _compile_text(s, o, t)
}

// compile_to_builder compiles IL held in memory and appends the generated
// assembly to builder (no intermediate file). Existing builder contents are
// kept; assembly is appended after them.
compile_to_builder :: proc(ssa_src: string, builder: ^strings.Builder, target := "") -> Error {
	s := strings.clone_to_cstring(ssa_src, context.temp_allocator)
	t := strings.clone_to_cstring(target, context.temp_allocator)
	out: [^]u8
	out_len: c.size_t
	if err := _compile_to_memory(s, t, &out, &out_len); err != .None {
		return err
	}
	defer _free_string(out)
	strings.write_bytes(builder, out[:int(out_len)])
	return .None
}

// compile_to_string is compile_to_builder collecting into a fresh string
// allocated with allocator.
compile_to_string :: proc(ssa_src: string, target := "", allocator := context.allocator) -> (string, Error) {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	if err := compile_to_builder(ssa_src, &b, target); err != .None {
		strings.builder_destroy(&b)
		return "", err
	}
	return strings.to_string(b), .None
}

// default_target returns the default backend for this build (e.g. "amd64_sysv").
default_target :: proc() -> string {
	return string(_default_target())
}

// set_debug mirrors qbe's -d flag: a string of debug letters (e.g. "P"),
// or "" to disable debug output.
set_debug :: proc(flags: string) {
	f := strings.clone_to_cstring(flags, context.temp_allocator)
	_set_debug(f)
}
