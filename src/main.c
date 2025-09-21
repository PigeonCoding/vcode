#include "compiler.h"
#include "flag.h"
#include "nob.h"
#include "simplex.h"
#include "types.h"

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

void usage(FILE *stream, const char *program) {
  fprintf(stream, "Usage: %s [OPTIONS] file.vc\n", program);
  fprintf(stream, "OPTIONS:\n");
  flag_print_options(stream);
}

bool s = false;

int main(int argc, char **argv) {

  int argcc = argc;
  char **argvv = argv;

  bool *help =
      flag_bool("help", false, "Print this help to stdout and exit with 0");
  bool *ssa = flag_bool("ssa", false, "Print generated C code to stdout");
  bool *silent = flag_bool("s", false, "silences messages");

  char **outb = flag_str(
      "o", "out",
      "sets the output file (any flag has to be set before the input file)");

  if (!flag_parse(argc, argv)) {
    usage(stderr, flag_program_name());
    exit(1);
  }

  argc = argcc;
  argv = argvv;

  if (*help) {
    usage(stdout, flag_program_name());
    exit(0);
  }

  if (*silent)
    s = true;

  char *file = NULL;

  for (int i = 0; i < argc && file == NULL; i++) {
    size_t len = strlen(argv[i]);
    if (*(argv[i]) != '-' && len >= 3 && argv[i][len - 3] == '.' &&
        argv[i][len - 2] == 'v' && argv[i][len - 1] == 'c') {
      file = argv[i];
    }
  }

  if (file == NULL) {
    fprintf(stderr, "please provide a source file\n");
    return 1;
  }

  lexer_t l = {0};

  if (!spx_init(file, &l))
    return 1;

  if (l.content.count <= 1) {
    fprintf(stderr, "the provided file (%s) is empty\n", *argv);
    return 1;
  }

  l.slash_comments = true;
  sb_appendf(&output,
             "#include <stdbool.h>\n#include <stdint.h>\n#include <stdio.h>\n\n");
  if (!s)
    nob_log(INFO, "prepass");
  if (prepass(&l))
    return 1;

  if (typedef_output.count > 0) {
    sb_appendf(&output, "\n");
    sb_appendf(&output, "%s", typedef_output.items);
    sb_appendf(&output, "\n");
  }

  sb_appendf(&output, "int main(void) {\n");
  if (!s)
    nob_log(INFO, "main pass");

  while (spx_get_token(&l)) {
    if (main_pass(&l, false))
      return 1;
  }

  sb_appendf(&output, "\n  return 0;\n}\n");
  da_append(&output, 0);

  if (*ssa) {
    printf("%s\n", output.items);
  }

  if (!nob_write_entire_file(temp_sprintf("%s.c", *outb), output.items,
                             output.count - 1))
    return 1;
  if (!s)
    nob_log(INFO, "wrote generated C to %s.c", *outb);

  return 0;
}
