#include "./src/compiler.c"
#include "./src/main.c"

Nob_String_Builder str_buf;
Nob_String_Builder output;
Nob_String_Builder typedef_output;

#define FLAG_IMPLEMENTATION
#include "./src/flag.h"

#define NOB_IMPLEMENTATION
#include "./src/nob.h"

#define SIMPLEX_IMPLEMENTATION
#include "./src/simplex.h"
