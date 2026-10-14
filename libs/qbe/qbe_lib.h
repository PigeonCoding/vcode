/* qbe_lib.h — QBE backend (vendored v1.3) as a linkable C library.
 *
 * QBE upstream only ships a `main()` driver (main.c). qbe_lib.c provides
 * the same compile pipeline behind this small API so vcode can link QBE
 * statically instead of shelling out to a `qbe` binary.
 *
 * Build with: make -C libs/qbe -f Makefile.lib libqbe.a
 * (libqbe.a = all QBE objects except main.o, plus qbe_lib.o)
 */
#ifndef QBE_LIB_H
#define QBE_LIB_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Return codes for qbe_compile_file / qbe_compile_text. */
enum {
	QBE_OK = 0,            /* assembly written to asm_path */
	QBE_ERR_IO = 1,        /* cannot open ssa_path / asm_path */
	QBE_ERR_TARGET = 2,    /* unknown target name */
};

/* Compile the QBE IL file at `ssa_path`, write assembly to `asm_path`.
 * `target` selects the backend (e.g. "amd64_sysv"); NULL or "" selects
 * the default target for this build (see qbe_default_target).
 * Returns QBE_OK / QBE_ERR_IO / QBE_ERR_TARGET. */
int qbe_compile_file(const char *ssa_path, const char *asm_path,
                     const char *target);

/* Same, but compiles IL source held in memory (`ssa_text` is NUL-
 * terminated QBE IL, e.g. emitted by vcode's code generator). */
int qbe_compile_text(const char *ssa_text, const char *asm_path,
                     const char *target);

/* Same as qbe_compile_text, but the generated assembly is returned in
 * memory instead of a file: on success `*out_asm` points to a NUL-
 * terminated heap buffer of `*out_len` bytes (length excludes the NUL),
 * owned by the caller and released with qbe_free_string(). On failure
 * `*out_asm` is NULL, `*out_len` is 0 and the return code tells why.
 * Useful for frontends (like vcode) that keep everything in memory. */
int qbe_compile_text_to_memory(const char *ssa_text, const char *target,
                               char **out_asm, size_t *out_len);

/* Release a buffer obtained from qbe_compile_text_to_memory(). */
void qbe_free_string(char *s);

/* Default target name for this build (e.g. "amd64_sysv"). Never NULL. */
const char *qbe_default_target(void);

/* Mirror of qbe's `-d` flag: `flags` is a string of debug letters
 * (e.g. "P" dumps after parsing); "" or NULL disables debug output. */
void qbe_set_debug(const char *flags);

/* NOTE ON ERRORS: like the `qbe` CLI, malformed IL aborts the process —
 * QBE's err()/die() call exit(). Only feed these procs IL you generated
 * yourself, or accept that a bad module kills the host, exactly as the
 * `qbe` binary would exit(1) on it. Sequential calls in one process are
 * fine (same as passing several files to the `qbe` CLI). */

#ifdef __cplusplus
}
#endif

#endif /* QBE_LIB_H */
