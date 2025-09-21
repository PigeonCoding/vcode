// Simplex v1 https://github.com/PigeonCoding/simplex.h

// example on how to use simplex
/*
  #define SIMPLEX_IMPLEMENTATION
  #include "simplex.h"

  int main() {
    lexer_t l = {0};
    // depending on what style you prefer
    l.slash_comments = true;
    l.pound_comments = true;

    if (!spx_init("./test.txt", &l))
      return 1;

    while (spx_get_token(&l)) {
      switch (l.token.type) {
      // do your stuff here
      }
    }

    spx_reset(&l); // if you need to reset the lexer and parse another file
  instead of creating a new one

    spx_free(&l);

  }

*/

#ifndef SIMPLEX_H_
#define SIMPLEX_H_

#include <errno.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

// this part is taken from nob - v1.23.0 - Public Domain -
// https://github.com/tsoding/nob.h just renamed as to not cause problems
// with using both simplex and nob at the same time

#ifdef __cplusplus
#define __DECLTYPE_CAST(T) (decltype(T))
#else
#define __DECLTYPE_CAST(T)
#endif // __cplusplus

#ifndef SPX_ASSERT
#include <assert.h>
#define SPX_ASSERT assert
#endif /* SPX_ASSERT */

#ifndef SPX_REALLOC
#include <stdlib.h>
#define SPX_REALLOC realloc
#endif /* SPX_REALLOC */

#ifndef SPX_FREE
#include <stdlib.h>
#define SPX_FREE free
#endif /* SPX_FREE */

#define spx_da_reserve(da, expected_capacity)                                  \
  do {                                                                         \
    if ((expected_capacity) > (da)->capacity) {                                \
      if ((da)->capacity == 0) {                                               \
        (da)->capacity = 128;                                                  \
      }                                                                        \
      while ((expected_capacity) > (da)->capacity) {                           \
        (da)->capacity *= 2;                                                   \
      }                                                                        \
      (da)->items = __DECLTYPE_CAST((da)->items)                               \
          SPX_REALLOC((da)->items, (da)->capacity * sizeof(*(da)->items));     \
      SPX_ASSERT((da)->items != NULL && "Buy more RAM lol");                   \
    }                                                                          \
  } while (0)

#define spx_da_append(da, item)                                                \
  do {                                                                         \
    spx_da_reserve((da), (da)->count + 1);                                     \
    (da)->items[(da)->count++] = (item);                                       \
  } while (0)

#define spx_da_free(da) SPX_FREE((da).items)

typedef struct {
  char *items;
  size_t count;
  size_t capacity;
} SPX_String_Builder;
typedef struct {
  const char **items;
  size_t count;
  size_t capacity;
} SPX_File_Paths;

#define __return_defer(value)                                                  \
  do {                                                                         \
    result = (value);                                                          \
    goto defer;                                                                \
  } while (0)

// taken from nob,h 'nob_read_entire_file'
bool spx_read_entire_file(const char *path, SPX_String_Builder *sb);

// -----------------------------------------------

#define MINUS_ATTACHED

extern bool tmp_bool;

enum SPX {
  SPX_eof,
  SPX_intlit,
  SPX_floatlit,
  SPX_id,
  SPX_dqstring,
  SPX_punct,
  SPX_charlit,
};

static const char *spx_type_to_str[] = {
    "SPX_eof",      "SPX_intlit", "SPX_floatlit", "SPX_id",
    "SPX_dqstring", "SPX_punct",  "SPX_charlit",
};

typedef struct {
  enum SPX type;
  char charlit;
  long intlit;
  double floatlit;
  // this is null terminated
  SPX_String_Builder str;

  uint16_t col;
  uint16_t row;
} token_t;

typedef struct {
  const char *file;
  SPX_String_Builder content;

  uint32_t cursor;
  uint16_t _col;
  uint16_t _row;

  // basically the // and /**/ comments
  bool slash_comments;
  // the # comments like in python
  bool pound_comments;
  bool raw_str;

  token_t token;

} lexer_t;

int spx_init(const char *file, lexer_t *l);
// returns true if a token is found
bool spx_get_token(lexer_t *l);
// this function does not modify the lexer
bool spx_check_puncts(lexer_t *l, int count, ...);
void spx_reset(lexer_t *l);
void spx_free(lexer_t *l);
lexer_t peak(lexer_t l);
bool spx_get_and_expect(lexer_t *l, enum SPX t);

#define _IS_LETTER(c)                                                          \
  (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_'
#define _IS_NUMERICAL(c) (c >= '0' && c <= '9')
#define _IS_ALPHANUMERICAL(c) (_IS_LETTER(c) || _IS_NUMERICAL(c))

#define _CC(l) (l)->content.items[(l)->cursor]

#define LOC "%s:%d:%d"
#define LOC_PRT(l) (l)->file, (l)->token.row, (l)->token.col
#define _PRT_ASSERT(cond, msg, ...)                                            \
  do {                                                                         \
    if (!(cond)) {                                                             \
      fprintf(stderr, msg, __VA_ARGS__);                                       \
      abort();                                                                 \
    }                                                                          \
  } while (0)

#define _INC_CURSOR(l, nl)                                                     \
  do {                                                                         \
    if (_CC(l) == '\n' && nl) {                                                \
      (l)->_col = 0;                                                           \
      (l)->_row++;                                                             \
      (l)->cursor++;                                                           \
    } else {                                                                   \
      (l)->cursor++;                                                           \
      (l)->_col++;                                                             \
    }                                                                          \
  } while (0)

// TODO: find a way to do it without tmp_bool
#define spx_check_puncts_n_skip(l, count, ...)                                 \
  do {                                                                         \
    tmp_bool = spx_check_puncts(l, count, __VA_ARGS__);                        \
    if (tmp_bool) {                                                            \
      for (int i = 1; i < count; i++) {                                        \
        spx_get_token(l);                                                      \
      }                                                                        \
    }                                                                          \
  } while (0);                                                                 \
  if (tmp_bool)

#define get_token_and_expect(l, type)                                          \
  spx_get_token((l)) && (l)->token.type == (type)
#define get_token_and_expect_punct(l, punct)                                   \
  get_token_and_expect(l, SPX_punct) && (l)->token.charlit == (punct)

// this function converts chars '0'-'9' to numbers 0-9
#define _char_to_nm(c)                                                         \
  (((c) == '1') * 1 + ((c) == '2') * 2 + ((c) == '3') * 3 + ((c) == '4') * 4 + \
   ((c) == '5') * 5 + ((c) == '6') * 6 + ((c) == '7') * 7 + ((c) == '8') * 8 + \
   ((c) == '9') * 9)

#endif // SIMPLEX_H_


// #define SIMPLEX_IMPLEMENTATION

#ifdef SIMPLEX_IMPLEMENTATION

bool tmp_bool = false;

int spx_init(const char *file, lexer_t *l) {
  l->content = (SPX_String_Builder){.count = 0};
  if (!spx_read_entire_file(file, &l->content)) {
    fprintf(stderr, "could not read file %s\n", file);
    return 0;
  }
  l->file = file;
  spx_da_append(&l->content, '\0');
  return 1;
}

bool spx_get_token(lexer_t *l) {

  l->token.type = SPX_eof;
  l->token.str.count = 0;
  l->token.charlit = 0;
  l->token.floatlit = 0;
  l->token.intlit = 0;
  l->token.col = 0;
  l->token.row = 0;

  while (_CC(l) == ' ' || _CC(l) == '\t' || _CC(l) == '\r' || _CC(l) == '\n') {
    _INC_CURSOR(l, true);
  }

  if (l->cursor >= l->content.count) {
    // fprintf(stdout, "[INFO]: EOF found");
    l->token.type = SPX_eof;
    return false;
  }

  if (l->slash_comments && l->cursor <= l->content.count - 2 && _CC(l) == '/' &&
      l->content.items[l->cursor + 1] == '/') {
    uint16_t row = l->_row;
    while (l->cursor < l->content.count && l->_row == row) {
      _INC_CURSOR(l, true);
    }
    return spx_get_token(l);
  }

  if (l->slash_comments && l->cursor <= l->content.count - 2 && _CC(l) == '/' &&
      l->content.items[l->cursor + 1] == '*') {
    // l->cursor++;
    while (l->cursor <= l->content.count - 2 &&
           !(_CC(l) == '*' && l->content.items[l->cursor + 1] == '/')) {

      _INC_CURSOR(l, true);
    }
    _INC_CURSOR(l, true);
    _INC_CURSOR(l, true);
    return spx_get_token(l);
  }

  if (l->pound_comments && _CC(l) == '#') {
    uint16_t row = l->_row;
    while (l->cursor < l->content.count && l->_row == row) {
      _INC_CURSOR(l, true);
    }
    return spx_get_token(l);
  }

  if (_IS_LETTER(_CC(l))) {
    l->token.col = l->_col + 1;
    l->token.row = l->_row + 1;

    while (_IS_ALPHANUMERICAL(_CC(l))) {
      spx_da_append(&l->token.str, _CC(l));
      _INC_CURSOR(l, false);
    }

    spx_da_append(&l->token.str, '\0');
    l->token.type = SPX_id;
  } else if (_CC(l) == '"') {
    l->token.col = l->_col + 1;
    l->token.row = l->_row + 1;

    _INC_CURSOR(l, false);

    while (_CC(l) != '"') {
      if (_CC(l) == '\\' && !l->raw_str) {
        uint16_t row = l->_row + 1;
        uint16_t col = l->_col + 1;
        _INC_CURSOR(l, false);
        switch (_CC(l)) {
        case 'b':
          spx_da_append(&l->token.str, '\b');
          break;
        case 'f':
          spx_da_append(&l->token.str, '\f');
          break;
        case 'n':
          spx_da_append(&l->token.str, '\n');
          break;
        case 'r':
          spx_da_append(&l->token.str, '\r');
          break;
        case 't':
          spx_da_append(&l->token.str, '\t');
          break;
        case 'v':
          spx_da_append(&l->token.str, '\v');
          break;
        case '\\':
          spx_da_append(&l->token.str, '\\');
          break;
        case '\'':
          break;
        case '"':
          spx_da_append(&l->token.str, '"');
          break;
        case '0':
          spx_da_append(&l->token.str, '\0');
          break;

        default:
          printf(LOC " unknown escape code here\n", l->file, row, col);
        }
        // spx_da_append(&l->token.str, _CC(l));
      } else {
        spx_da_append(&l->token.str, _CC(l));
      }
      _INC_CURSOR(l, false);
    }
    spx_da_append(&l->token.str, '\0');
    l->token.type = SPX_dqstring;
    _INC_CURSOR(l, true);

  } else if (_IS_NUMERICAL(_CC(l))) {
    l->token.col = l->_col + 1;
    l->token.row = l->_row + 1;

    l->token.type = SPX_intlit;
    while (_IS_NUMERICAL(_CC(l))) {
      l->token.intlit *= 10;
      l->token.intlit += _char_to_nm(_CC(l));
      _INC_CURSOR(l, false);
    }

    if (l->token.intlit != 0 && _CC(l) == '#') {
      int base = l->token.intlit;
      l->token.intlit = 0;
      _INC_CURSOR(l, false);
      const char *current = l->content.items + l->cursor;

      while (_IS_ALPHANUMERICAL(_CC(l))) {
        l->token.intlit *= 10;
        l->token.intlit += _char_to_nm(_CC(l));
        _INC_CURSOR(l, false);
      }

      char tmp = _CC(l);
      _CC(l) = '\0';
      l->token.intlit = strtoull(current, NULL, base);
      _CC(l) = tmp;
    } else if (l->token.intlit == 0 && _CC(l) == 'x') {
      int base = 16;
      // l->token.intlit = 0;
      _INC_CURSOR(l, false);
      const char *current = l->content.items + l->cursor;

      while (_IS_ALPHANUMERICAL(_CC(l))) {
        l->token.intlit *= 10;
        l->token.intlit += _char_to_nm(_CC(l));
        _INC_CURSOR(l, false);
      }

      char tmp = _CC(l);
      _CC(l) = '\0';
      l->token.intlit = strtoull(current, NULL, base);
      _CC(l) = tmp;
    } else if (l->token.intlit == 0 && _CC(l) == 'o') {
      int base = 8;
      // l->token.intlit = 0;
      _INC_CURSOR(l, false);
      const char *current = l->content.items + l->cursor;

      while (_IS_ALPHANUMERICAL(_CC(l))) {
        l->token.intlit *= 10;
        l->token.intlit += _char_to_nm(_CC(l));
        _INC_CURSOR(l, false);
      }

      char tmp = _CC(l);
      _CC(l) = '\0';
      l->token.intlit = strtoull(current, NULL, base);
      _CC(l) = tmp;
    } else if (l->token.intlit == 0 && _CC(l) == 'b') {
      int base = 2;
      // l->token.intlit = 0;
      _INC_CURSOR(l, false);
      const char *current = l->content.items + l->cursor;

      while (_IS_ALPHANUMERICAL(_CC(l))) {
        l->token.intlit *= 10;
        l->token.intlit += _char_to_nm(_CC(l));
        _INC_CURSOR(l, false);
      }

      char tmp = _CC(l);
      _CC(l) = '\0';
      l->token.intlit = strtoull(current, NULL, base);
      _CC(l) = tmp;
    }

    if (_CC(l) == '.') {
      // TODO: optimize it maybe
      l->token.type = SPX_floatlit;
      l->token.floatlit = l->token.intlit;
      l->token.intlit = 1;

      _INC_CURSOR(l, false);

      while (_IS_NUMERICAL(_CC(l))) {
        l->token.intlit *= 10;
        l->token.intlit += _char_to_nm(_CC(l));
        _INC_CURSOR(l, false);
      }

      float f = l->token.intlit;
      while (abs((int)(f)) > 1)
        f /= 10;

      l->token.floatlit += f - 1;
      l->token.intlit = 0;
    }

  } else if (_CC(l) == '\'') {
    l->token.col = l->_col + 1;
    l->token.row = l->_row + 1;

    _INC_CURSOR(l, false);
    l->token.charlit = _CC(l);
    l->token.type = SPX_charlit;
    _INC_CURSOR(l, false);

    _PRT_ASSERT(_CC(l) == '\'',
                LOC " single quote strings are not supported, "
                    "either use double quote or fix your char\n",
                LOC_PRT(l));
    _INC_CURSOR(l, true);
  } else {
    if (_CC(l) == 0)
      return false;
    bool yes = false;

    if (_CC(l) == '-') {
      uint16_t t = l->cursor;
      _INC_CURSOR(l, false);

      if (
#ifdef MINUS_ATTACHED
          _IS_NUMERICAL(_CC(l)) &&
#endif
          spx_get_token(l) &&
          (l->token.type == SPX_floatlit || l->token.type == SPX_intlit)) {
        yes = true;
        if (l->token.type == SPX_intlit) {
          l->token.intlit = -l->token.intlit;
        } else if (l->token.type == SPX_floatlit) {
          l->token.floatlit = -l->token.floatlit;
        }
        l->token.col -= 1;
      } else {
        l->cursor = t;
      }
    }

    if (!yes) {
      l->token.col = l->_col + 1;
      l->token.row = l->_row + 1;
      l->token.charlit = _CC(l);
      l->token.type = SPX_punct;
      _INC_CURSOR(l, true);
    }
  }

  return true;
}

bool spx_check_puncts(lexer_t *l, int count, ...) {

  token_t token = l->token;
  size_t _row = l->_row;
  size_t _col = l->_col;
  size_t cursor = l->cursor;

  va_list args;
  va_start(args, count);

  for (int i = 0; i < count; i++) {
    if (l->token.charlit == va_arg(args, int)) {
      spx_get_token(l);
      continue;
    } else {

      l->token = token;
      l->_row = _row;
      l->_col = _col;
      l->cursor = cursor;

      va_end(args);
      return false;
    }
  }

  l->token = token;
  l->_row = _row;
  l->_col = _col;
  l->cursor = cursor;

  va_end(args);
  return true;
}

void spx_reset(lexer_t *l) {
  l->cursor = 0;
  l->_col = 0;
  l->_row = 0;

  l->token.type = SPX_eof;
  l->token.str.count = 0;
  l->token.charlit = 0;
  l->token.floatlit = 0;
  l->token.intlit = 0;
  l->token.col = 0;
  l->token.row = 0;
}

void spx_free(lexer_t *l) {
  spx_reset(l);

  l->file = NULL;

  spx_da_free(l->content);
  l->content.items = NULL;
  l->content.capacity = 0;
  l->content.count = 0;

  spx_da_free(l->token.str);
  l->token.str.items = NULL;
  l->token.str.capacity = 0;
  l->token.str.count = 0;
}

// -------------------------------
// TODO: points to the same str
// as the base lexer so no memory leak
// but it overwrites the old str
lexer_t peak(lexer_t l) {
  if (!spx_get_token(&l))
    l.token.type = SPX_eof;
  return l;
}

bool spx_get_and_expect(lexer_t *l, enum SPX t) {

  if (!spx_get_token(l)) {
    if ((int)t == -1)
      fprintf(stderr, "[ERROR]: " LOC " got eof\n", LOC_PRT(l));
    else
      fprintf(stderr, "[ERROR]: " LOC " expected (%s) but got eof\n", LOC_PRT(l),
              spx_type_to_str[t]);
    return false;
  }

  if ((int)t != -1 && l->token.type != t) {
    fprintf(stderr, "[ERROR]: " LOC " expected (%s) but got (%s)\n", LOC_PRT(l),
            spx_type_to_str[t], spx_type_to_str[l->token.type]);
    return false;
  }

  return true;
}

//---------------------------------

bool spx_read_entire_file(const char *path, SPX_String_Builder *sb) {
  bool result = true;

  FILE *f = fopen(path, "rb");
  size_t new_count = 0;
  long long m = 0;
  if (f == NULL)
    __return_defer(false);
  if (fseek(f, 0, SEEK_END) < 0)
    __return_defer(false);
#ifndef _WIN32
  m = ftell(f);
#else
  m = _ftelli64(f);
#endif
  if (m < 0)
    __return_defer(false);
  if (fseek(f, 0, SEEK_SET) < 0)
    __return_defer(false);

  new_count = sb->count + m;
  if (new_count > sb->capacity) {
    sb->items = __DECLTYPE_CAST(sb->items) SPX_REALLOC(sb->items, new_count);
    SPX_ASSERT(sb->items != NULL && "Buy more RAM lool!!");
    sb->capacity = new_count;
  }

  fread(sb->items + sb->count, m, 1, f);
  if (ferror(f)) {
    // TODO: Afaik, ferror does not set errno. So the error reporting in defer
    // is not correct in this case.
    __return_defer(false);
  }
  sb->count = new_count;

defer:
  if (!result)
    fprintf(stderr, "Could not read file %s: %s\n", path, strerror(errno));
  if (f)
    fclose(f);
  return result;
}
// ------------------------------
#endif