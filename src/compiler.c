#include "compiler.h"
#include "simplex.h"
#include "types.h"
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static int str_pass(lexer_t *l);
static int fn_pass(lexer_t *l);
static int parse_fn_decl_args(lexer_t *l);
static int parse_struct_decl(lexer_t *l);
static const char *type_tag_to_c(char t);
static void emit_c_escaped_string(Nob_String_Builder *out, const char *s);
static void emit_source_line(Nob_String_Builder *out, lexer_t *l);
static bool is_struct_type(const char *type_name);
static void register_struct_type(const char *type_name);
static const char *resolve_decl_type(lexer_t *l, uint64_t *tag_off, char *buf,
                                     size_t buf_size, bool *is_custom_type);
static bool type_tag_is_integer(char t);
static bool type_tag_is_float(char t);
static bool type_tag_is_numeric(char t);
static bool type_is_assignable(char lhs_tag, const char *lhs_custom, char rhs_tag,
                               const char *rhs_custom);
static char join_numeric_types(char lhs_tag, char rhs_tag);
static uint32_t intern_type_tag(char t);

typedef struct {
  uint64_t name;
} Struct_Type_t;

struct {
  Struct_Type_t *items;
  uint32_t count;
  uint32_t capacity;
} struct_types = {0};

int type_to_tag(lexer_t *l) {

  if (strcmp(l->token.str.items, "i32") == 0) {
    sb_appendf(&str_buf, "w");
    da_append(&str_buf, 0);
  } else if (strcmp(l->token.str.items, "i64") == 0) {
    sb_appendf(&str_buf, "l");
    da_append(&str_buf, 0);
  } else if (strcmp(l->token.str.items, "f32") == 0) {
    sb_appendf(&str_buf, "s");
    da_append(&str_buf, 0);
  } else if (strcmp(l->token.str.items, "f64") == 0) {
    sb_appendf(&str_buf, "d");
    da_append(&str_buf, 0);
  } else if (strcmp(l->token.str.items, "u8") == 0 ||
             strcmp(l->token.str.items, "byte") == 0 ||
             strcmp(l->token.str.items, "ubyte") == 0) {
    sb_appendf(&str_buf, "u");
    da_append(&str_buf, 0);
  } else if (strcmp(l->token.str.items, "u16") == 0) {
    sb_appendf(&str_buf, "v");
    da_append(&str_buf, 0);
  } else if (strcmp(l->token.str.items, "i8") == 0) {
    sb_appendf(&str_buf, "c");
    da_append(&str_buf, 0);
  } else if (strcmp(l->token.str.items, "i16") == 0) {
    sb_appendf(&str_buf, "h");
    da_append(&str_buf, 0);
  } else if (strcmp(l->token.str.items, "bool") == 0) {
    sb_appendf(&str_buf, "o");
    da_append(&str_buf, 0);
  }

  return 0;
}

static bool is_struct_type(const char *type_name) {
  for (uint32_t i = 0; i < struct_types.count; i++) {
    if (strcmp(type_name, &str_buf.items[struct_types.items[i].name]) == 0) {
      return true;
    }
  }
  return false;
}

static void register_struct_type(const char *type_name) {
  if (is_struct_type(type_name)) {
    return;
  }

  da_append(&struct_types, (Struct_Type_t){0});
  da_last(&struct_types).name = str_buf.count;
  sb_appendf(&str_buf, "%s", type_name);
  da_append(&str_buf, 0);
}

static const char *resolve_decl_type(lexer_t *l, uint64_t *tag_off, char *buf,
                                     size_t buf_size, bool *is_custom_type) {
  uint64_t local_tag_off = 0;
  if (tag_off) {
    *tag_off = 0;
  }
  if (is_custom_type) {
    *is_custom_type = false;
  }

  if (strcmp(l->token.str.items, "i32") == 0 ||
      strcmp(l->token.str.items, "i64") == 0 ||
      strcmp(l->token.str.items, "f32") == 0 ||
      strcmp(l->token.str.items, "f64") == 0 ||
      strcmp(l->token.str.items, "u8") == 0 ||
      strcmp(l->token.str.items, "u16") == 0 ||
      strcmp(l->token.str.items, "i8") == 0 ||
      strcmp(l->token.str.items, "i16") == 0 ||
      strcmp(l->token.str.items, "byte") == 0 ||
      strcmp(l->token.str.items, "ubyte") == 0 ||
      strcmp(l->token.str.items, "bool") == 0) {
    uint64_t *effective_tag_off = tag_off ? tag_off : &local_tag_off;
    *effective_tag_off = str_buf.count;
    type_to_tag(l);
    return type_tag_to_c(str_buf.items[*effective_tag_off]);
  }

  if (is_struct_type(l->token.str.items)) {
    snprintf(buf, buf_size, "%s", l->token.str.items);
    if (is_custom_type) {
      *is_custom_type = true;
    }
    return buf;
  }

  return NULL;
}

static const char *type_tag_to_c(char t) {
  switch (t) {
  case 'w':
    return "int32_t";
  case 'l':
    return "int64_t";
  case 's':
    return "float";
  case 'd':
    return "double";
  case 'u':
    return "uint8_t";
  case 'v':
    return "uint16_t";
  case 'c':
    return "int8_t";
  case 'h':
    return "int16_t";
  case 'o':
    return "bool";
  default:
    return "int64_t";
  }
}

static bool type_tag_is_integer(char t) {
  return t == 'w' || t == 'l' || t == 'u' || t == 'v' || t == 'c' || t == 'h';
}

static bool type_tag_is_float(char t) { return t == 's' || t == 'd'; }

static bool type_tag_is_numeric(char t) {
  return type_tag_is_integer(t) || type_tag_is_float(t);
}

static uint32_t intern_type_tag(char t) {
  uint32_t off = str_buf.count;
  da_append(&str_buf, t);
  da_append(&str_buf, 0);
  return off;
}

static char join_numeric_types(char lhs_tag, char rhs_tag) {
  if (lhs_tag == 'd' || rhs_tag == 'd')
    return 'd';
  if (lhs_tag == 's' || rhs_tag == 's')
    return 's';
  if (lhs_tag == 'l' || rhs_tag == 'l')
    return 'l';
  if (lhs_tag == 'w' || rhs_tag == 'w')
    return 'w';
  if (lhs_tag == 'v' || rhs_tag == 'v')
    return 'v';
  if (lhs_tag == 'h' || rhs_tag == 'h')
    return 'h';
  if (lhs_tag == 'u' || rhs_tag == 'u')
    return 'u';
  return 'c';
}

static bool type_is_assignable(char lhs_tag, const char *lhs_custom, char rhs_tag,
                               const char *rhs_custom) {
  if (lhs_tag == 'T' || rhs_tag == 'T') {
    if (lhs_tag != 'T' || rhs_tag != 'T') {
      return false;
    }
    if (lhs_custom == NULL || rhs_custom == NULL) {
      return false;
    }
    return strcmp(lhs_custom, rhs_custom) == 0;
  }

  if (lhs_tag == 'o' || rhs_tag == 'o') {
    return lhs_tag == rhs_tag;
  }

  if (lhs_tag == 'p' || rhs_tag == 'p') {
    return lhs_tag == rhs_tag;
  }

  if (type_tag_is_numeric(lhs_tag) && type_tag_is_numeric(rhs_tag)) {
    return true;
  }

  return lhs_tag == rhs_tag;
}

static void emit_c_escaped_string(Nob_String_Builder *out, const char *s) {
  sb_appendf(out, "\"");
  for (const unsigned char *p = (const unsigned char *)s; *p; ++p) {
    switch (*p) {
    case '\\':
      sb_appendf(out, "\\\\");
      break;
    case '"':
      sb_appendf(out, "\\\"");
      break;
    case '\n':
      sb_appendf(out, "\\n");
      break;
    case '\r':
      sb_appendf(out, "\\r");
      break;
    case '\t':
      sb_appendf(out, "\\t");
      break;
    default:
      sb_appendf(out, "%c", *p);
      break;
    }
  }
  sb_appendf(out, "\"");
}

static void emit_source_line(Nob_String_Builder *out, lexer_t *l) {
  if (l->file == NULL || l->token.row == 0) {
    return;
  }

  sb_appendf(out, "#line %u ", l->token.row);
  emit_c_escaped_string(out, l->file);
  sb_appendf(out, "\n");
}

static enum VC_Kws get_keyword(lexer_t *l) {

  switch (l->token.type) {
  case SPX_id:
    if (strcmp(l->token.str.items, "let") == 0)
      return VC_Let_Kw;
    else if (strcmp(l->token.str.items, "if") == 0)
      return VC_If_Kw;
    else if (strcmp(l->token.str.items, "while") == 0)
      return VC_While_Kw;
    else if (strcmp(l->token.str.items, "fn") == 0)
      return VC_Fn_Kw;
    else if (strcmp(l->token.str.items, "struct") == 0)
      return VC_Struct_Kw;

    break;

  case SPX_eof:
  case SPX_intlit:
  case SPX_floatlit:
  case SPX_dqstring:
  case SPX_punct:
  case SPX_charlit:
    break;
  }

  return VC_none_Kw;
}

static enum VC_Puncts get_punct(lexer_t *l) {
  switch (l->token.type) {
  case SPX_punct:

    spx_check_puncts_n_skip(l, 2, '=', '=') { return VC_Eq_Punct; }
    spx_check_puncts_n_skip(l, 2, '+', '+') { return VC_PP_Punct; }
    spx_check_puncts_n_skip(l, 2, '-', '-') { return VC_MM_Punct; }

    if (l->token.charlit == '+')
      return VC_Add_Punct;
    else if (l->token.charlit == '-')
      return VC_Sub_Punct;
    else if (l->token.charlit == '*')
      return VC_Mult_Punct;
    else if (l->token.charlit == '/')
      return VC_Div_Punct;
    else if (l->token.charlit == '%')
      return VC_Mod_Punct;
    else if (l->token.charlit == '=')
      return VC_Assign_Punct;
    else if (l->token.charlit == '<')
      return VC_Less_Punct;
    else if (l->token.charlit == '>')
      return VC_Gr_Punct;

    if (l->token.charlit == '{') {
      while (spx_get_and_expect(l, -1) && l->token.charlit != '}') {
        if (main_pass(l, false))
          return VC_error_Punct;
      }
      spx_get_token(l);
    }

    if (l->token.charlit == '(') {
      while (spx_get_and_expect(l, -1) && l->token.charlit != ')') {
        if (main_pass(l, false))
          return VC_error_Punct;
      }
      spx_get_token(l);
    }

    break;
  case SPX_eof:
  case SPX_intlit:
  case SPX_floatlit:
  case SPX_id:
  case SPX_dqstring:
  case SPX_charlit:
    break;
  }

  return VC_none_Punct;
}

typedef struct {
  uint32_t type;
  uint32_t index;
} C_t;
C_t counter = {0};
static char last_lvalue[256] = {0};
static bool has_last_lvalue = false;
static char last_lvalue_tag = 0;
static char last_lvalue_custom[128] = {0};
static bool has_last_lvalue_type = false;
static char last_value_tag = 0;
static char last_value_custom[128] = {0};
static bool has_last_value_type = false;

typedef struct {
  uint32_t cursor;
  uint32_t type;
  uint64_t name;
} LUT_t;

struct {
  LUT_t *items;
  uint32_t count;
  uint32_t capacity;
} lut = {0};

typedef struct {
  uint64_t name;
  uint64_t typedef_name;
} Fn_Var_Type_t;

struct {
  Fn_Var_Type_t *items;
  uint32_t count;
  uint32_t capacity;
} fn_var_types = {0};

static char last_fn_typedef[128] = {0};
static bool has_last_fn_typedef = false;

static const char *lookup_fn_var_typedef(const char *name) {
  for (uint32_t i = 0; i < fn_var_types.count; i++) {
    if (strcmp(name, &str_buf.items[fn_var_types.items[i].name]) == 0) {
      return &str_buf.items[fn_var_types.items[i].typedef_name];
    }
  }
  return NULL;
}

static void set_fn_var_typedef(const char *name, const char *typedef_name) {
  for (uint32_t i = 0; i < fn_var_types.count; i++) {
    if (strcmp(name, &str_buf.items[fn_var_types.items[i].name]) == 0) {
      fn_var_types.items[i].typedef_name = str_buf.count;
      sb_appendf(&str_buf, "%s", typedef_name);
      da_append(&str_buf, 0);
      return;
    }
  }

  da_append(&fn_var_types, (Fn_Var_Type_t){0});
  da_last(&fn_var_types).name = str_buf.count;
  sb_appendf(&str_buf, "%s", name);
  da_append(&str_buf, 0);
  da_last(&fn_var_types).typedef_name = str_buf.count;
  sb_appendf(&str_buf, "%s", typedef_name);
  da_append(&str_buf, 0);
}

int prepass(lexer_t *l) {
  da_append(&str_buf, 'l');
  l->raw_str = true;
  while (spx_get_token(l)) {
    if (str_pass(l))
      return 1;
  }
  spx_reset(l);
  l->raw_str = false;
  while (spx_get_token(l)) {
    if (fn_pass(l))
      return 1;
  }
  spx_reset(l);
  // l->raw_str = false;
  return 0;
}

static int str_pass(lexer_t *l) {
  switch (l->token.type) {
  case SPX_dqstring:
    break;
  case SPX_eof:
  case SPX_punct:
  case SPX_intlit:
  case SPX_floatlit:
  case SPX_id:
  case SPX_charlit:
    break;
  }

  return 0;
}

static int parse_fn_decl_args(lexer_t *l) {
  if (!spx_get_token(l))
    return 1;
  sb_appendf(&output, "(");
  while (l->token.charlit != ')') {
    if (l->token.type != SPX_id) {
      nob_log(ERROR, LOC " expected argument name but got %s", LOC_PRT(l),
              spx_type_to_str[l->token.type]);
      return 1;
    }

    char arg_name[l->token.str.count + 1];
    memcpy(arg_name, l->token.str.items, l->token.str.count);
    arg_name[l->token.str.count] = 0;

    if (!spx_get_and_expect(l, SPX_punct))
      return 1;
    if (l->token.charlit != ':') {
      nob_log(ERROR, LOC " expected ':' after argument name", LOC_PRT(l));
      return 1;
    }

    if (!spx_get_and_expect(l, SPX_id))
      return 1;
    uint64_t t = 0;
    char arg_type_buf[128] = {0};
    bool is_custom_type = false;
    const char *arg_type =
        resolve_decl_type(l, &t, arg_type_buf, sizeof(arg_type_buf), &is_custom_type);
    if (arg_type == NULL) {
      nob_log(ERROR, LOC " unknown type (%s) in function arguments", LOC_PRT(l),
              l->token.str.items);
      return 1;
    }
    sb_appendf(&output, "%s %s", arg_type, arg_name);

    da_append(&lut, (LUT_t){0});
    da_last(&lut).cursor = (uint32_t)-1;
    da_last(&lut).name = str_buf.count;
    sb_appendf(&str_buf, "%s", arg_name);
    da_append(&str_buf, 0);
    da_last(&lut).type = is_custom_type ? 0 : t;
    if (is_custom_type) {
      set_fn_var_typedef(arg_name, arg_type);
    }

    if (!spx_get_token(l))
      return 1;

    if (l->token.type == SPX_punct && l->token.charlit == ',') {
      sb_appendf(&output, ", ");
      if (!spx_get_token(l))
        return 1;
    }
  }
  sb_appendf(&output, ")");

  return 0;
}

static int parse_struct_decl(lexer_t *l) {
  if (!spx_get_and_expect(l, SPX_id))
    return 1;

  char struct_name[128] = {0};
  snprintf(struct_name, sizeof(struct_name), "%s", l->token.str.items);
  register_struct_type(struct_name);

  if (!spx_get_and_expect(l, SPX_punct))
    return 1;
  if (l->token.charlit != '{') {
    nob_log(ERROR, LOC " expected '{' after struct name", LOC_PRT(l));
    return 1;
  }

  emit_source_line(&typedef_output, l);
  sb_appendf(&typedef_output, "typedef struct {\n");

  while (spx_get_token(l)) {
    if (l->token.type == SPX_punct && l->token.charlit == '}')
      break;

    if (l->token.type != SPX_id) {
      nob_log(ERROR, LOC " expected field name in struct declaration", LOC_PRT(l));
      return 1;
    }

    char field_name[128] = {0};
    snprintf(field_name, sizeof(field_name), "%s", l->token.str.items);

    if (!spx_get_and_expect(l, SPX_punct))
      return 1;
    if (l->token.charlit != ':') {
      nob_log(ERROR, LOC " expected ':' after struct field name", LOC_PRT(l));
      return 1;
    }

    if (!spx_get_and_expect(l, SPX_id))
      return 1;
    char field_type[128] = {0};
    bool is_custom_type = false;
    const char *c_type =
        resolve_decl_type(l, NULL, field_type, sizeof(field_type), &is_custom_type);
    if (c_type == NULL) {
      nob_log(ERROR, LOC " unknown type (%s) in struct field", LOC_PRT(l),
              l->token.str.items);
      return 1;
    }

    sb_appendf(&typedef_output, "  %s %s;\n", c_type, field_name);

    if (!spx_get_and_expect(l, SPX_punct))
      return 1;
    if (l->token.charlit == ',')
      continue;
    if (l->token.charlit == '}')
      break;

    nob_log(ERROR, LOC " expected ',' or '}' after struct field declaration",
            LOC_PRT(l));
    return 1;
  }

  if (l->token.type != SPX_punct || l->token.charlit != '}') {
    nob_log(ERROR, LOC " expected '}' to close struct declaration", LOC_PRT(l));
    return 1;
  }

  if (!spx_get_and_expect(l, SPX_punct))
    return 1;
  if (l->token.charlit != ';') {
    nob_log(ERROR, LOC " expected ';' after struct declaration", LOC_PRT(l));
    return 1;
  }

  sb_appendf(&typedef_output, "} %s;\n", struct_name);
  return 0;
}

static int fn_pass(lexer_t *l) {

  switch (l->token.type) {
  case SPX_id:
    switch (get_keyword(l)) {

    case VC_Struct_Kw:
      if (parse_struct_decl(l))
        return 1;
      break;

    case VC_Fn_Kw:

      da_append(&lut, (LUT_t){0});
      da_last(&lut).cursor = l->cursor;
      uint32_t *ttt = &da_last(&lut).type;

      if (!spx_get_token(l))
        return 1;

      if (l->token.type == SPX_punct && l->token.charlit == '(') {
        da_append(&lut, (LUT_t){0});
        da_last(&lut).name = str_buf.count;
        sb_appendf(&str_buf, "anofunc_%d", counter.index++);
        da_append(&str_buf, 0);
      } else if (l->token.type == SPX_id) {
        da_append(&lut, (LUT_t){0});
        da_last(&lut).name = str_buf.count;
        sb_appendf(&str_buf, "%s", l->token.str.items);
        da_append(&str_buf, 0);
        if (!spx_get_and_expect(l, SPX_punct))
          return 1;
      } else {
        nob_log(ERROR, LOC " expected either () or id but got %s", LOC_PRT(l),
                spx_type_to_str[l->token.type]);
        return 1;
      }

      const char *fn_name = &str_buf.items[da_last(&lut).name];
      uint32_t ret_type_off = output.count;
      emit_source_line(&output, l);
      sb_appendf(&output, "int64_t %s", fn_name);
      uint32_t args_off = output.count;

      if (parse_fn_decl_args(l))
        return 1;
      uint32_t args_end = output.count;
      size_t args_len = args_end - args_off;
      if (args_len >= 1024) {
        nob_log(ERROR, LOC "function signature is too long", LOC_PRT(l));
        return 1;
      }
      char args_sig[1024];
      memcpy(args_sig, &output.items[args_off], args_len);
      args_sig[args_len] = 0;

      if (!spx_get_token(l))
        return 1;
      if (!spx_get_and_expect(l, SPX_id))
        return 1;

      uint64_t ll = 0;
      char ret_type_buf[128] = {0};
      bool is_custom_type = false;
      const char *ret_type =
          resolve_decl_type(l, &ll, ret_type_buf, sizeof(ret_type_buf), &is_custom_type);
      if (ret_type == NULL) {
        nob_log(ERROR, LOC " unknown return type (%s)", LOC_PRT(l),
                l->token.str.items);
        return 1;
      }
      da_last(&lut).type = is_custom_type ? 0 : ll;
      output.count = ret_type_off;
      sb_appendf(&output, "%s %s", ret_type, fn_name);
      sb_appendf(&output, "%s", args_sig);

      char fn_typedef[160] = {0};
      snprintf(fn_typedef, sizeof(fn_typedef), "%s_t", fn_name);
      emit_source_line(&typedef_output, l);
      sb_appendf(&typedef_output, "typedef %s (*%s)%s;\n", ret_type, fn_typedef,
                 args_sig);

      sb_appendf(&output, " {\n");

      if (!spx_get_token(l))
        return 1;

      if (main_pass(l, false))
        return 1;

      sb_appendf(&output, "  return 0;\n}\n\n");

      switch (l->token.type) {
      case SPX_id:
        *ttt = l->cursor - l->token.str.count;
        break;
      case SPX_punct:
        *ttt = l->cursor - 1;
        break;
      case SPX_intlit:
      case SPX_floatlit:
      case SPX_dqstring:
      case SPX_charlit:
      case SPX_eof:
        *ttt = l->cursor;

        break;
      }
      break;

    case VC_none_Kw:
    case VC_Let_Kw:
    case VC_While_Kw:
    case VC_If_Kw:
      break;
    }
    break;
  case SPX_dqstring:
  case SPX_eof:
  case SPX_punct:
  case SPX_intlit:
  case SPX_floatlit:
  case SPX_charlit:
    break;
  }

  return 0;
}

int main_pass(lexer_t *l, bool skip) {
  if (!skip && l->token.type != SPX_eof) {
    emit_source_line(&output, l);
  }

  switch (l->token.type) {
  case SPX_intlit:
    if (!skip) {
      char t = 'l';
      if (counter.type < str_buf.count &&
          (str_buf.items[counter.type] == 'w' || str_buf.items[counter.type] == 'l' ||
           str_buf.items[counter.type] == 's' || str_buf.items[counter.type] == 'd' ||
           str_buf.items[counter.type] == 'u' || str_buf.items[counter.type] == 'v' ||
           str_buf.items[counter.type] == 'c' || str_buf.items[counter.type] == 'h' ||
           str_buf.items[counter.type] == 'o')) {
        t = str_buf.items[counter.type];
      }
      sb_appendf(&output, "  %s t%d = %ld;\n", type_tag_to_c(t), counter.index++,
                 l->token.intlit);
      last_value_tag = t;
      last_value_custom[0] = 0;
      has_last_value_type = true;
      counter.type = intern_type_tag(t);
    }
    break;

  case SPX_floatlit:
    if (!skip) {
      char t = 'd';
      if (counter.type < str_buf.count &&
          (str_buf.items[counter.type] == 's' || str_buf.items[counter.type] == 'd')) {
        t = str_buf.items[counter.type];
      }
      sb_appendf(&output, "  %s t%d = %f;\n", type_tag_to_c(t), counter.index++,
                 l->token.floatlit);
      last_value_tag = t;
      last_value_custom[0] = 0;
      has_last_value_type = true;
      counter.type = intern_type_tag(t);
    }
    break;

  case SPX_punct:
    C_t c;
    switch (get_punct(l)) {

    case VC_Assign_Punct:

      while (spx_get_token(l)) {
        if (main_pass(l, false))
          return 1;
        if (l->token.type == SPX_punct && l->token.charlit == ';') {
          break;
        }
      }

      if (has_last_lvalue && has_last_lvalue_type && has_last_value_type) {
        if (!type_is_assignable(last_lvalue_tag, last_lvalue_custom, last_value_tag,
                                last_value_custom)) {
          nob_log(ERROR, LOC " type mismatch in assignment to %s", LOC_PRT(l),
                  last_lvalue);
          return 1;
        }
      }

      if (!skip && has_last_lvalue)
        sb_appendf(&output, "  %s = t%d;\n", last_lvalue, counter.index - 1);

      break;
    case VC_Add_Punct:

      c = counter;
      c.index--;
      char lhs_tag_add = 0;
      if (counter.type < str_buf.count) {
        lhs_tag_add = str_buf.items[counter.type];
      }

      if (!spx_get_token(l)) {
        return 1;
      }

      if (main_pass(l, false))
        return 1;

      char rhs_tag_add = has_last_value_type ? last_value_tag : 0;
      if (!type_tag_is_numeric(lhs_tag_add) || !type_tag_is_numeric(rhs_tag_add)) {
        nob_log(ERROR, LOC " '+' expects numeric operands", LOC_PRT(l));
        return 1;
      }
      char res_tag_add = join_numeric_types(lhs_tag_add, rhs_tag_add);

      if (!skip)
        sb_appendf(&output, "  %s t%d = t%d + t%d;\n", type_tag_to_c(res_tag_add),
                   counter.index,
                   c.index, counter.index - 1);
      counter.index++;
      counter.type = intern_type_tag(res_tag_add);
      last_value_tag = res_tag_add;
      last_value_custom[0] = 0;
      has_last_value_type = true;

      break;
    case VC_Sub_Punct:
      c = counter;
      c.index--;
      char lhs_tag_sub = 0;
      if (counter.type < str_buf.count) {
        lhs_tag_sub = str_buf.items[counter.type];
      }

      if (!spx_get_token(l)) {
        return 1;
      }

      if (main_pass(l, false))
        return 1;

      char rhs_tag_sub = has_last_value_type ? last_value_tag : 0;
      if (!type_tag_is_numeric(lhs_tag_sub) || !type_tag_is_numeric(rhs_tag_sub)) {
        nob_log(ERROR, LOC " '-' expects numeric operands", LOC_PRT(l));
        return 1;
      }
      char res_tag_sub = join_numeric_types(lhs_tag_sub, rhs_tag_sub);

      if (!skip)
        sb_appendf(&output, "  %s t%d = t%d - t%d;\n", type_tag_to_c(res_tag_sub),
                   counter.index,
                   c.index, counter.index - 1);
      counter.index++;
      counter.type = intern_type_tag(res_tag_sub);
      last_value_tag = res_tag_sub;
      last_value_custom[0] = 0;
      has_last_value_type = true;

      break;
    case VC_Mod_Punct:
      c = counter;
      c.index--;
      char lhs_tag_mod = 0;
      if (counter.type < str_buf.count) {
        lhs_tag_mod = str_buf.items[counter.type];
      }

      if (!spx_get_token(l)) {
        return 1;
      }

      if (main_pass(l, false))
        return 1;

      char rhs_tag_mod = has_last_value_type ? last_value_tag : 0;
      if (!type_tag_is_integer(lhs_tag_mod) || !type_tag_is_integer(rhs_tag_mod)) {
        nob_log(ERROR, LOC " '%%' expects integer operands", LOC_PRT(l));
        return 1;
      }
      char res_tag_mod = join_numeric_types(lhs_tag_mod, rhs_tag_mod);

      if (!skip)
        sb_appendf(&output, "  %s t%d = t%d %% t%d;\n", type_tag_to_c(res_tag_mod),
                   counter.index,
                   c.index, counter.index - 1);
      counter.index++;
      counter.type = intern_type_tag(res_tag_mod);
      last_value_tag = res_tag_mod;
      last_value_custom[0] = 0;
      has_last_value_type = true;

      break;
    case VC_Mult_Punct:
      c = counter;
      c.index--;
      char lhs_tag_mul = 0;
      if (counter.type < str_buf.count) {
        lhs_tag_mul = str_buf.items[counter.type];
      }

      if (!spx_get_token(l)) {
        return 1;
      }

      if (main_pass(l, false))
        return 1;

      char rhs_tag_mul = has_last_value_type ? last_value_tag : 0;
      if (!type_tag_is_numeric(lhs_tag_mul) || !type_tag_is_numeric(rhs_tag_mul)) {
        nob_log(ERROR, LOC " '*' expects numeric operands", LOC_PRT(l));
        return 1;
      }
      char res_tag_mul = join_numeric_types(lhs_tag_mul, rhs_tag_mul);

      if (!skip)
        sb_appendf(&output, "  %s t%d = t%d * t%d;\n", type_tag_to_c(res_tag_mul),
                   counter.index,
                   c.index, counter.index - 1);
      counter.index++;
      counter.type = intern_type_tag(res_tag_mul);
      last_value_tag = res_tag_mul;
      last_value_custom[0] = 0;
      has_last_value_type = true;

      break;
    case VC_Div_Punct:
      c = counter;
      c.index--;
      char lhs_tag_div = 0;
      if (counter.type < str_buf.count) {
        lhs_tag_div = str_buf.items[counter.type];
      }

      if (!spx_get_token(l)) {
        return 1;
      }

      if (main_pass(l, false))
        return 1;

      char rhs_tag_div = has_last_value_type ? last_value_tag : 0;
      if (!type_tag_is_numeric(lhs_tag_div) || !type_tag_is_numeric(rhs_tag_div)) {
        nob_log(ERROR, LOC " '/' expects numeric operands", LOC_PRT(l));
        return 1;
      }
      char res_tag_div = join_numeric_types(lhs_tag_div, rhs_tag_div);

      if (!skip)
        sb_appendf(&output, "  %s t%d = t%d / t%d;\n", type_tag_to_c(res_tag_div),
                   counter.index,
                   c.index, counter.index - 1);
      counter.index++;
      counter.type = intern_type_tag(res_tag_div);
      last_value_tag = res_tag_div;
      last_value_custom[0] = 0;
      has_last_value_type = true;

      break;
    case VC_Eq_Punct:

      c = counter;
      c.index--;
      char lhs_tag_eq = 0;
      if (counter.type < str_buf.count) {
        lhs_tag_eq = str_buf.items[counter.type];
      }

      if (!spx_get_token(l)) {
        return 1;
      }

      if (main_pass(l, false))
        return 1;

      char rhs_tag_eq = has_last_value_type ? last_value_tag : 0;
      if (!type_is_assignable(lhs_tag_eq, NULL, rhs_tag_eq, NULL) &&
          !type_is_assignable(rhs_tag_eq, NULL, lhs_tag_eq, NULL)) {
        nob_log(ERROR, LOC " '==' expects compatible operand types", LOC_PRT(l));
        return 1;
      }

      if (!skip)
        sb_appendf(&output, "  int32_t t%d = t%d == t%d;\n", counter.index,
                   c.index, counter.index - 1);
      counter.index++;
      counter.type = intern_type_tag('o');
      last_value_tag = 'o';
      last_value_custom[0] = 0;
      has_last_value_type = true;

      break;
    case VC_PP_Punct:
      if (!skip && has_last_lvalue)
        sb_appendf(&output, "  ++%s;\n", last_lvalue);
      break;
    case VC_MM_Punct:
      if (!skip && has_last_lvalue) {
        sb_appendf(&output, "  --%s;\n", last_lvalue);
      }
      break;
    case VC_Less_Punct:
      c = counter;
      c.index--;
      char lhs_tag_lt = 0;
      if (counter.type < str_buf.count) {
        lhs_tag_lt = str_buf.items[counter.type];
      }

      if (!spx_get_token(l)) {
        return 1;
      }

      if (main_pass(l, false))
        return 1;

      char rhs_tag_lt = has_last_value_type ? last_value_tag : 0;
      if (!type_tag_is_numeric(lhs_tag_lt) || !type_tag_is_numeric(rhs_tag_lt)) {
        nob_log(ERROR, LOC " '<' expects numeric operands", LOC_PRT(l));
        return 1;
      }

      if (!skip)
        sb_appendf(&output, "  int32_t t%d = t%d < t%d;\n", counter.index, c.index,
                   counter.index - 1);
      counter.index++;
      counter.type = intern_type_tag('o');
      last_value_tag = 'o';
      last_value_custom[0] = 0;
      has_last_value_type = true;
      break;
    case VC_Gr_Punct:
      c = counter;
      c.index--;
      char lhs_tag_gt = 0;
      if (counter.type < str_buf.count) {
        lhs_tag_gt = str_buf.items[counter.type];
      }

      if (!spx_get_token(l)) {
        return 1;
      }

      if (main_pass(l, false))
        return 1;

      char rhs_tag_gt = has_last_value_type ? last_value_tag : 0;
      if (!type_tag_is_numeric(lhs_tag_gt) || !type_tag_is_numeric(rhs_tag_gt)) {
        nob_log(ERROR, LOC " '>' expects numeric operands", LOC_PRT(l));
        return 1;
      }

      if (!skip)
        sb_appendf(&output, "  int32_t t%d = t%d > t%d;\n", counter.index, c.index,
                   counter.index - 1);
      counter.index++;
      counter.type = intern_type_tag('o');
      last_value_tag = 'o';
      last_value_custom[0] = 0;
      has_last_value_type = true;
      break;
    case VC_error_Punct:
      return 1;
    case VC_none_Punct:
      break;
    }
    break;

  case SPX_id:
    switch (get_keyword(l)) {

    case VC_Let_Kw:
      // TODO: check if any other symbol have the same name
      if (!spx_get_and_expect(l, SPX_id))
        return 1;

      da_append(&lut, (LUT_t){0});
      // i sure do hope no one ever writes a single
      // file with 4294967295 chars
      da_last(&lut).cursor = -1;
      da_last(&lut).name = str_buf.count;
      char var_name[128] = {0};
      if (!skip)
        sb_appendf(&str_buf, "%s", l->token.str.items);
      snprintf(var_name, sizeof(var_name), "%s", l->token.str.items);
      if (!skip)
        da_append(&str_buf, 0);

      if (!spx_get_and_expect(l, SPX_punct))
        return 1;

      if (!spx_get_and_expect(l, SPX_id))
        return 1;

      da_last(&lut).type = 0;
      uint64_t decl_tag = 0;
      char decl_type_buf[128] = {0};
      bool is_custom_decl_type = false;
      const char *decl_type =
          resolve_decl_type(l, &decl_tag, decl_type_buf, sizeof(decl_type_buf),
                            &is_custom_decl_type);
      if (decl_type == NULL) {
        nob_log(ERROR, LOC " unknown type (%s) in variable declaration", LOC_PRT(l),
                l->token.str.items);
        return 1;
      }
      if (!is_custom_decl_type) {
        da_last(&lut).type = decl_tag;
      } else {
        set_fn_var_typedef(var_name, decl_type);
      }
      char decl_expected_tag =
          is_custom_decl_type ? 'T' : str_buf.items[da_last(&lut).type];
      char decl_expected_custom[128] = {0};
      if (is_custom_decl_type) {
        snprintf(decl_expected_custom, sizeof(decl_expected_custom), "%s", decl_type);
      }
      char inferred_decl_type[128] = {0};

      if (!spx_get_and_expect(l, SPX_punct))
        return 1;

      if (l->token.charlit == '=') {
        LUT_t temp = da_last(&lut);
        bool first_token = true;
        has_last_fn_typedef = false;
        if (!is_custom_decl_type) {
          counter.type = decl_tag;
        }
        while (spx_get_token(l)) {
          if (first_token && l->token.type == SPX_id &&
              get_keyword(l) == VC_none_Kw) {
            const char *rhs_typedef = lookup_fn_var_typedef(l->token.str.items);
            if (rhs_typedef) {
              snprintf(inferred_decl_type, sizeof(inferred_decl_type), "%s",
                       rhs_typedef);
            }
          }
          if (main_pass(l, false))
            return 1;
          if (first_token && has_last_fn_typedef) {
            snprintf(inferred_decl_type, sizeof(inferred_decl_type), "%s",
                     last_fn_typedef);
          }
          first_token = false;
          if (l->token.type == SPX_punct && l->token.charlit == ';')
            break;
        }
        char final_decl_tag = decl_expected_tag;
        char final_decl_custom[128] = {0};
        if (decl_expected_tag == 'T') {
          snprintf(final_decl_custom, sizeof(final_decl_custom), "%s",
                   decl_expected_custom);
        }
        if (inferred_decl_type[0]) {
          final_decl_tag = 'T';
          snprintf(final_decl_custom, sizeof(final_decl_custom), "%s",
                   inferred_decl_type);
        }
        if (has_last_value_type &&
            !type_is_assignable(final_decl_tag, final_decl_custom, last_value_tag,
                                last_value_custom)) {
          nob_log(ERROR, LOC " type mismatch in initializer for %s", LOC_PRT(l),
                  var_name);
          return 1;
        }
        if (!skip) {
          const char *final_decl_type =
              inferred_decl_type[0] ? inferred_decl_type : decl_type;
          emit_source_line(&output, l);
          sb_appendf(&output, "  %s %s;\n", final_decl_type,
                     &str_buf.items[temp.name]);
        }
        if (!skip) {
          emit_source_line(&output, l);
          sb_appendf(&output, "  %s = t%d;\n", &str_buf.items[temp.name],
                     counter.index - 1);
        }
        if (inferred_decl_type[0]) {
          set_fn_var_typedef(var_name, inferred_decl_type);
        }
      } else if (!skip) {
        emit_source_line(&output, l);
        sb_appendf(&output, "  %s %s;\n", decl_type,
                   &str_buf.items[da_last(&lut).name]);
      }
      has_last_lvalue = true;
      snprintf(last_lvalue, sizeof(last_lvalue), "%s",
               &str_buf.items[da_last(&lut).name]);
      has_last_lvalue_type = true;
      if (inferred_decl_type[0]) {
        last_lvalue_tag = 'T';
        snprintf(last_lvalue_custom, sizeof(last_lvalue_custom), "%s",
                 inferred_decl_type);
      } else {
        last_lvalue_tag = decl_expected_tag;
        if (decl_expected_tag == 'T') {
          snprintf(last_lvalue_custom, sizeof(last_lvalue_custom), "%s",
                   decl_expected_custom);
        } else {
          last_lvalue_custom[0] = 0;
        }
      }

      break;

    case VC_If_Kw:

      if (!spx_get_token(l))
        return 1;

      if (main_pass(l, false))
        return 1;

      if (!skip)
        sb_appendf(&output, "  if (t%d) {\n", counter.index - 1);

      if (main_pass(l, false))
        return 1;
      if (!skip)
        sb_appendf(&output, "  }\n");

      if (l->token.charlit == ')') {
        if (!spx_get_token(l))
          return 1;
      }
      if (l->token.charlit == ';') {
        if (!spx_get_token(l))
          return 1;
      }

      if (strcmp(l->token.str.items, "else") == 0) {
        if (!spx_get_token(l))
          return 1;

        if (!skip)
          sb_appendf(&output, "  else {\n");

        if (main_pass(l, false))
          return 1;

        if (!skip)
          sb_appendf(&output, "  }\n");
      }

      break;

    case VC_While_Kw:

      if (!skip)
        sb_appendf(&output, "  while (1) {\n");

      if (!spx_get_token(l))
        return 1;

      if (main_pass(l, false))
        return 1;

      if (!skip)
        sb_appendf(&output, "  if (!t%d) break;\n", counter.index - 1);

      // printf("%s", output.items);
      // exit(0);

      if (main_pass(l, false))
        return 1;

      if (!skip)
        sb_appendf(&output, "  }\n");
      break;

    case VC_Fn_Kw:

      for (uint32_t i = 0; i < lut.count; i++) {
        if (lut.items[i].cursor == l->cursor) {
          const char *fn_name = &str_buf.items[lut.items[i + 1].name];
          snprintf(last_fn_typedef, sizeof(last_fn_typedef), "%s_t", fn_name);
          has_last_fn_typedef = true;

          if (!skip)
            sb_appendf(&output, "  %s t%d = &%s;\n", last_fn_typedef,
                       counter.index++, fn_name);
          counter.type = 0;
          last_value_tag = 'T';
          snprintf(last_value_custom, sizeof(last_value_custom), "%s",
                   last_fn_typedef);
          has_last_value_type = true;

          int brace_depth = 0;
          bool seen_body = false;
          while (spx_get_token(l)) {
            if (l->token.type != SPX_punct)
              continue;

            if (l->token.charlit == '{') {
              seen_body = true;
              brace_depth++;
            } else if (l->token.charlit == '}') {
              if (brace_depth > 0)
                brace_depth--;
              if (seen_body && brace_depth == 0)
                break;
            }
          }

          return 0;
        }
      }

      nob_log(ERROR,
              LOC " this function has no cursor skip, it was probably not "
                  "analyzed, shit",
              LOC_PRT(l));
      return 1;

      break;

    case VC_Struct_Kw: {
      int brace_depth = 0;
      bool seen_body = false;
      while (spx_get_token(l)) {
        if (l->token.type != SPX_punct)
          continue;
        if (l->token.charlit == '{') {
          seen_body = true;
          brace_depth++;
        } else if (l->token.charlit == '}') {
          if (brace_depth > 0)
            brace_depth--;
          if (seen_body && brace_depth == 0)
            break;
        }
      }

      if (!spx_get_and_expect(l, SPX_punct))
        return 1;
      if (l->token.charlit != ';') {
        nob_log(ERROR, LOC " expected ';' after struct declaration", LOC_PRT(l));
        return 1;
      }
      break;
    }

    case VC_none_Kw:

      char temp[l->token.str.count + 1];
      memcpy(temp, l->token.str.items, l->token.str.count);
      temp[l->token.str.count] = 0;

      if (strcmp(temp, "true") == 0 || strcmp(temp, "false") == 0) {
        if (!skip)
          sb_appendf(&output, "  bool t%u = %s;\n", counter.index++, temp);
        counter.type = intern_type_tag('o');
        last_value_tag = 'o';
        last_value_custom[0] = 0;
        has_last_value_type = true;
        return 0;
      }

      if (peak(*l).token.charlit == '(') {
        C_t args[32] = {0};
        unsigned char arg = 0;
        const char *var_typedef = lookup_fn_var_typedef(temp);
        bool call_via_var = false;
        for (uint32_t i = 0; i < lut.count; i++) {
          if (lut.items[i].cursor == (uint32_t)-1 &&
              strcmp(temp, &str_buf.items[lut.items[i].name]) == 0) {
            call_via_var = true;
            break;
          }
        }

        if ((spx_get_token((l)) && (l)->token.type == (SPX_punct) &&
             (l)->token.charlit == ('('))) {
          if (peak(*l).token.charlit != ')') {
            bool quit = false;
            while (!quit && spx_get_token(l)) {
              if (l->token.type == SPX_punct && l->token.charlit == ')') {
                quit = true;
              }

              if (main_pass(l, false)) {
                return 1;
              }
              if (l->token.type == SPX_punct &&
                  (l->token.charlit == ',' || l->token.charlit == ')')) {
                args[arg] = counter;
                args[arg].index--;
                arg++;
              }
            }
          }
        }

        if (!skip) {
          if (call_via_var && var_typedef) {
            sb_appendf(&output, "  int64_t t%d = %s(", counter.index++, temp);
          } else if (call_via_var) {
            sb_appendf(&output,
                       "  int64_t t%d = ((int64_t (*)())(uintptr_t)%s)(",
                       counter.index++, temp);
          } else {
            sb_appendf(&output, "  int64_t t%d = %s(", counter.index++, temp);
          }
        }
        for (int i = 0; i < arg; i++) {
          if (!skip)
            sb_appendf(&output, "t%d%s", args[i].index, i + 1 == arg ? "" : ", ");
        }
        if (!skip)
          sb_appendf(&output, ");\n");
        counter.type = intern_type_tag('l');
        last_value_tag = 'l';
        last_value_custom[0] = 0;
        has_last_value_type = true;
        return 0;
      }

      bool y = false;
      bool member_access = false;
      char member_expr[256] = {0};
      for (uint32_t i = 0; i < lut.count; i++) {
        if (lut.items[i].cursor == (uint32_t)-1 &&
            strcmp(temp, &str_buf.items[lut.items[i].name]) == 0) {
          const char *var_typedef = lookup_fn_var_typedef(temp);
          if (!skip) {
            if (var_typedef) {
              sb_appendf(&output, "  %s t%u = %s;\n", var_typedef, counter.index++,
                         &str_buf.items[lut.items[i].name]);
            } else {
              sb_appendf(&output, "  %s t%u = %s;\n",
                         type_tag_to_c(str_buf.items[lut.items[i].type]),
                         counter.index++, &str_buf.items[lut.items[i].name]);
            }
          }
          counter.type = var_typedef ? 0 : lut.items[i].type;
          has_last_lvalue = true;
          snprintf(last_lvalue, sizeof(last_lvalue), "%s",
                   &str_buf.items[lut.items[i].name]);
          has_last_lvalue_type = true;
          if (var_typedef) {
            last_lvalue_tag = 'T';
            snprintf(last_lvalue_custom, sizeof(last_lvalue_custom), "%s",
                     var_typedef);
            last_value_tag = 'T';
            snprintf(last_value_custom, sizeof(last_value_custom), "%s", var_typedef);
            has_last_value_type = true;
          } else {
            last_lvalue_tag = str_buf.items[lut.items[i].type];
            last_lvalue_custom[0] = 0;
            last_value_tag = str_buf.items[lut.items[i].type];
            last_value_custom[0] = 0;
            has_last_value_type = true;
          }
          y = true;

          if (peak(*l).token.type == SPX_punct && peak(*l).token.charlit == '.') {
            snprintf(member_expr, sizeof(member_expr), "%s", temp);
            while (peak(*l).token.type == SPX_punct &&
                   peak(*l).token.charlit == '.') {
              if (!spx_get_and_expect(l, SPX_punct))
                return 1;
              if (l->token.charlit != '.') {
                nob_log(ERROR, LOC " expected '.' for member access", LOC_PRT(l));
                return 1;
              }
              if (!spx_get_and_expect(l, SPX_id))
                return 1;

              size_t len = strlen(member_expr);
              int wrote = snprintf(member_expr + len, sizeof(member_expr) - len,
                                   ".%s", l->token.str.items);
              if (wrote < 0 || (size_t)wrote >= sizeof(member_expr) - len) {
                nob_log(ERROR, LOC " member access is too long", LOC_PRT(l));
                return 1;
              }
            }
            member_access = true;
          }
          break;
        }
      }

      if (!y) {
        nob_log(ERROR, LOC "id (%s) is unknown", LOC_PRT(l), temp);
        return 1;
      }

      if (member_access) {
        if (!skip)
          sb_appendf(&output, "  int64_t t%u = %s;\n", counter.index++,
                     member_expr);
        counter.type = intern_type_tag('l');
        last_value_tag = 'l';
        last_value_custom[0] = 0;
        has_last_value_type = true;
        has_last_lvalue = true;
        snprintf(last_lvalue, sizeof(last_lvalue), "%s", member_expr);
        has_last_lvalue_type = false;
      }

      break;
    }
    break;

  case SPX_dqstring:
    if (!skip) {
      sb_appendf(&output, "  const char *t%d = ", counter.index++);
      emit_c_escaped_string(&output, l->token.str.items);
      sb_appendf(&output, ";\n");
    }
    counter.type = intern_type_tag('p');
    last_value_tag = 'p';
    last_value_custom[0] = 0;
    has_last_value_type = true;
    break;
  case SPX_eof:
    return 1;
  default:
    printf("unknown %s\n", spx_type_to_str[l->token.type]);
    return 1;
  }

  return 0;
}
