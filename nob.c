#include <assert.h>

#if defined(__GNUC__) && !defined(__llvm__) && !defined(__INTEL_COMPILER)
#define REAL_GCC __GNUC__ // probably
#endif

#ifndef nob_cc

#if _WIN32

#if defined(__GNUC__)
#define nob_cc(cmd)                                                            \
  nob_cmd_append(cmd, "x86_64-w64-mingw32-gcc",                                \
                 "-DCCC=\"x86_64-w64-mingw32-gcc\"")
#else
#define nob_cc(cmd)                                                            \
  nob_cmd_append(cmd, "clang", "-DCCC=\"clang\"", "-Wno-c23-extensions")
#endif

#else

#if defined(REAL_GCC)
#define nob_cc(cmd) nob_cmd_append(cmd, "cc", "-DCCC=\"cc\"")
#elif defined(__clang__)
#define nob_cc(cmd)                                                            \
  nob_cmd_append(cmd, "clang", "-DCCC=\"clang\"", "-Wno-c23-extensions")
#endif

#endif

#endif // nob_cc

#ifndef NOB_REBUILD_URSELF

#if defined(_WIN32)

#if defined(__GNUC__)
#define NOB_REBUILD_URSELF(binary_path, source_path)                           \
  "x86_64-w64-mingw32-gcc", "-o", binary_path, source_path
#else
#define NOB_REBUILD_URSELF(binary_path, source_path)                           \
  "clang", "-Wno-c23-extensions", "-o", binary_path, source_path
#endif

#else

#if defined(REAL_GCC)
#define NOB_REBUILD_URSELF(binary_path, source_path)                           \
  "gcc", "-o", binary_path, source_path
#else
#define NOB_REBUILD_URSELF(binary_path, source_path)                           \
  "clang", "-Wno-c23-extensions", "-o", binary_path, source_path
#endif

#endif
#endif

#define NOB_IMPLEMENTATION
#define NOB_STRIP_PREFIX
#include "src/nob.h"

bool s = false;

#define BUILD "build/"
#define FLAGS                                                                  \
  "-g", "-Wall", "-Wextra", "-Wno-comment", "-Wswitch",                        \
      "-Wimplicit-fallthrough", "-Wno-unused-command-line-argument"

static const char *src_files[] = {
    "src/compiler.c", "src/flag.h",    "src/nob.h",
    "src/simplex.h",  "src/types.h",   "src/compiler.h",
    "src/main.c",     "one.c",
};

bool vcode(Cmd *cmd) {
  if (nob_needs_rebuild(BUILD "vcode", src_files, ARRAY_LEN(src_files))) {
    nob_cc(cmd);

    cmd_append(cmd, "one.c", "-o", BUILD "vcode");
    cmd_append(cmd, FLAGS);

    return cmd_run(cmd);
  }
  return true;
}

bool make_dirs() { return nob_mkdir_if_not_exists(BUILD); }

#define generate_file(file, procs)                                             \
  do {                                                                         \
    cmd_append(&cmd, BUILD "vcode", "-o", BUILD file, "-s",                    \
               "examples/" file ".vc");                                        \
    if (!cmd_run(&cmd, .async = procs, .max_procs = 5)) {                      \
      return 1;                                                                \
    }                                                                          \
  } while (0)
#define compile_c_file(file, procs)                                            \
  do {                                                                         \
    nob_cc(&cmd);                                                              \
    cmd_append(&cmd, file, "-o", file ".out");                                \
    if (!cmd_run(&cmd, .async = procs, .max_procs = 5)) {                      \
      return 1;                                                                \
    }                                                                          \
  } while (0)

const bool GENERATE_ALL = true;

int main(int argc, char **argv) {

  NOB_GO_REBUILD_URSELF(argc, argv);
  if (!make_dirs())
    return 1;

  Cmd cmd = {0};
  if (!vcode(&cmd))
    return 1;

  if (GENERATE_ALL) {
    Nob_Procs procs = {0};
    generate_file("hello", &procs);
    generate_file("if", &procs);
    generate_file("ops", &procs);
    generate_file("pp_mm", &procs);
    generate_file("while", &procs);
    generate_file("functions", &procs);
    generate_file("struct", &procs);
    generate_file("types", &procs);
    if (!nob_procs_wait(procs))
      return 1;

    procs.count = 0;
    compile_c_file(BUILD "hello.c", &procs);
    compile_c_file(BUILD "if.c", &procs);
    compile_c_file(BUILD "ops.c", &procs);
    compile_c_file(BUILD "pp_mm.c", &procs);
    compile_c_file(BUILD "while.c", &procs);
    compile_c_file(BUILD "functions.c", &procs);
    compile_c_file(BUILD "struct.c", &procs);
    compile_c_file(BUILD "types.c", &procs);
    if (!nob_procs_wait(procs))
      return 1;
  }

  return 0;
}
