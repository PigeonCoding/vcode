/* qbe_lib — QBE backend (vendored v1.3) as a linkable C library.
 *
 * Implements qbe_lib.h. The compile pipeline (qbe_data/qbe_func pass
 * order, target list, debug flags) is copied from main.c's static
 * functions so the library behaves exactly like the `qbe` driver;
 * only the CLI option parsing / process lifetime is replaced.
 *
 * main.o is excluded from libqbe.a, so this file owns the globals
 * main.c normally defines (T, debug).
 */

/* _POSIX_C_SOURCE for open_memstream() (used by
 * qbe_compile_text_to_memory); must precede all includes. */
#define _POSIX_C_SOURCE 200809L

#include "all.h"
#include "config.h"
#include "qbe_lib.h"

#include <ctype.h>
#include <stdio.h>
#include <string.h>

/* --- globals normally owned by main.c (excluded from the library) --- */

Target T;

char debug['Z'+1] = {
	['P'] = 0, /* parsing */
	['M'] = 0, /* memory optimization */
	['N'] = 0, /* ssa construction */
	['C'] = 0, /* copy elimination */
	['G'] = 0, /* gvn/gcm */
	['K'] = 0, /* if-conversion */
	['A'] = 0, /* abi lowering */
	['I'] = 0, /* instruction selection */
	['L'] = 0, /* liveness */
	['S'] = 0, /* spilling */
	['R'] = 0, /* reg. allocation */
};

extern Target T_amd64_sysv;
extern Target T_amd64_apple;
extern Target T_amd64_win;
extern Target T_arm64;
extern Target T_arm64_apple;
extern Target T_rv64;

static Target *tlist[] = {
	&T_amd64_sysv,
	&T_amd64_apple,
	&T_amd64_win,
	&T_arm64,
	&T_arm64_apple,
	&T_rv64,
	0
};

/* Output file + debug-dump mode for the current compilation
 * (same role as main.c's statics). */
static FILE *lib_outf;
static int lib_dbg;

/* --- pipeline callbacks (cf. main.c data/func/dbgfile) --- */

static void
qbe_data(Dat *d)
{
	if (lib_dbg)
		return;
	emitdat(d, lib_outf);
	if (d->type == DEnd) {
		fputs("/* end data */\n\n", lib_outf);
		freeall();
	}
}

static void
qbe_func(Fn *fn)
{
	uint n;

	if (lib_dbg)
		fprintf(stderr, "**** Function %s ****", fn->name);
	if (debug['P']) {
		fprintf(stderr, "\n> After parsing:\n");
		printfn(fn, stderr);
	}
	T.abi0(fn);
	fillcfg(fn);
	filluse(fn);
	promote(fn);
	filluse(fn);
	ssa(fn);
	filluse(fn);
	ssacheck(fn);
	fillalias(fn);
	loadopt(fn);
	filluse(fn);
	fillalias(fn);
	coalesce(fn);
	filluse(fn);
	filldom(fn);
	ssacheck(fn);
	gvn(fn);
	fillcfg(fn);
	simplcfg(fn);
	filluse(fn);
	filldom(fn);
	gcm(fn);
	filluse(fn);
	ssacheck(fn);
	if (T.cansel) {
		ifconvert(fn);
		fillcfg(fn);
		filluse(fn);
		filldom(fn);
		ssacheck(fn);
	}
	T.abi1(fn);
	simpl(fn);
	fillcfg(fn);
	filluse(fn);
	T.isel(fn);
	fillcfg(fn);
	filllive(fn);
	fillloop(fn);
	fillcost(fn);
	spill(fn);
	rega(fn);
	fillcfg(fn);
	simpljmp(fn);
	fillcfg(fn);
	assert(fn->rpo[0] == fn->start);
	for (n=0;; n++)
		if (n == fn->nblk-1) {
			fn->rpo[n]->link = 0;
			break;
		} else
			fn->rpo[n]->link = fn->rpo[n+1];
	if (!lib_dbg) {
		T.emitfn(fn, lib_outf);
		fprintf(lib_outf, "/* end function %s */\n\n", fn->name);
	} else
		fprintf(stderr, "\n");
	freeall();
}

static void
qbe_dbgfile(char *fn)
{
	emitdbgfile(fn, lib_outf);
}

/* --- target selection (cf. main.c -t handling) --- */

static int
qbe_select_target(const char *target)
{
	Target **t;

	T = Deftgt;
	if (!target || !*target)
		return 0;
	for (t=tlist;; t++) {
		if (!*t)
			return -1;
		if (strcmp(target, (*t)->name) == 0) {
			T = **t;
			return 0;
		}
	}
}

/* --- driver core shared by file/text/memory entry points --- */

static int
qbe_run_stream(FILE *inf, const char *in_name, FILE *outf,
               const char *target)
{
	if (qbe_select_target(target) != 0)
		return QBE_ERR_TARGET;
	lib_outf = outf;
	parse(inf, (char *)in_name, qbe_dbgfile, qbe_data, qbe_func);
	if (!lib_dbg)
		T.emitfin(lib_outf);
	return QBE_OK;
}

static int
qbe_run(FILE *inf, const char *in_name, const char *asm_path,
        const char *target)
{
	FILE *outf;
	int rc;

	/* Select the target first so an unknown name does not truncate
	 * an existing output file. */
	if (qbe_select_target(target) != 0)
		return QBE_ERR_TARGET;
	outf = fopen(asm_path, "w");
	if (!outf) {
		fprintf(stderr, "qbe: cannot open '%s'\n", asm_path);
		return QBE_ERR_IO;
	}
	rc = qbe_run_stream(inf, in_name, outf, target);
	fclose(outf);
	return rc;
}

int
qbe_compile_file(const char *ssa_path, const char *asm_path,
                 const char *target)
{
	FILE *inf;
	int rc;

	if (!ssa_path || !asm_path)
		return QBE_ERR_IO;
	inf = fopen(ssa_path, "r");
	if (!inf) {
		fprintf(stderr, "qbe: cannot open '%s'\n", ssa_path);
		return QBE_ERR_IO;
	}
	rc = qbe_run(inf, ssa_path, asm_path, target);
	fclose(inf);
	return rc;
}

int
qbe_compile_text(const char *ssa_text, const char *asm_path,
                 const char *target)
{
	FILE *tmp;
	int rc;

	if (!ssa_text || !asm_path)
		return QBE_ERR_IO;
	tmp = tmpfile();
	if (!tmp) {
		fprintf(stderr, "qbe: cannot create temporary file\n");
		return QBE_ERR_IO;
	}
	fputs(ssa_text, tmp);
	rewind(tmp);
	rc = qbe_run(tmp, "<text>", asm_path, target);
	fclose(tmp);
	return rc;
}

const char *
qbe_default_target(void)
{
	return Deftgt.name;
}

int
qbe_compile_text_to_memory(const char *ssa_text, const char *target,
                           char **out_asm, size_t *out_len)
{
	FILE *tmp, *mem;
	char *buf;
	size_t len;
	int rc;

	if (!ssa_text || !out_asm || !out_len)
		return QBE_ERR_IO;
	*out_asm = 0;
	*out_len = 0;
	tmp = tmpfile();
	if (!tmp) {
		fprintf(stderr, "qbe: cannot create temporary file\n");
		return QBE_ERR_IO;
	}
	fputs(ssa_text, tmp);
	rewind(tmp);
	mem = open_memstream(&buf, &len);
	if (!mem) {
		fprintf(stderr, "qbe: cannot create memory stream\n");
		fclose(tmp);
		return QBE_ERR_IO;
	}
	rc = qbe_run_stream(tmp, "<text>", mem, target);
	fclose(tmp);
	fclose(mem); /* flushes the stream into buf/len */
	if (rc != QBE_OK) {
		free(buf);
		return rc;
	}
	if (!buf) {
		/* No output at all (e.g. debug mode): hand out an
		 * empty string rather than NULL. */
		buf = malloc(1);
		if (!buf)
			return QBE_ERR_IO;
		buf[0] = 0;
		len = 0;
	}
	*out_asm = buf;
	*out_len = len;
	return QBE_OK;
}

void
qbe_free_string(char *s)
{
	free(s);
}

void
qbe_set_debug(const char *flags)
{
	const char *f;

	memset(debug, 0, sizeof debug);
	lib_dbg = 0;
	for (f=flags; f && *f; f++)
		if (isalpha((unsigned char)*f)) {
			debug[toupper((unsigned char)*f)] = 1;
			lib_dbg = 1;
		}
}
