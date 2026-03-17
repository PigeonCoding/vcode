#ifndef DSTRING_H
#define DSTRING_H

/*
  dstring.h - simple dynamic string
  This library maintains a null-terminated buffer. All append operations
  ensure `data[len] == '\0'`.
*/

#include <stddef.h> /* size_t */
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct DString {
  char *data;
  size_t len;
  size_t cap;
} DString;

void ds_init(DString *s);
void ds_free(DString *s);

bool ds_reserve(DString *s, size_t min_cap);

void ds_clear(DString *s);
bool ds_append(DString *s, const char *buf, size_t n);
bool ds_append_cstr(DString *s, const char *cstr);
bool ds_append_char(DString *s, char c);

static inline const char *ds_c_str(const DString *s) {
  return (s && s->data) ? s->data : "";
}
static inline size_t ds_len(const DString *s) {
  return s ? s->len : 0;
}

#ifdef __cplusplus
}
#endif

#endif /* DSTRING_H */

#ifdef DSTRING_IMPLEMENTATION

#include <stdlib.h>
#include <string.h>

static bool ds__grow(DString *s, size_t min_cap) {
  size_t new_cap = s->cap ? s->cap : 16;
  while (new_cap < min_cap) {
    size_t next = new_cap * 2;
    if (next < new_cap) {
      return false;
    }
    new_cap = next;
  }

  char *new_data = (char *)realloc(s->data, new_cap);
  if (!new_data) {
    return false;
  }

  s->data = new_data;
  s->cap = new_cap;
  return true;
}

void ds_init(DString *s) {
  if (!s) return;
  s->data = NULL;
  s->len = 0;
  s->cap = 0;
}

void ds_free(DString *s) {
  if (!s) return;
  free(s->data);
  s->data = NULL;
  s->len = 0;
  s->cap = 0;
}

bool ds_reserve(DString *s, size_t min_cap) {
  if (!s) return false;
  if (s->cap >= min_cap) return true;
  return ds__grow(s, min_cap);
}

void ds_clear(DString *s) {
  if (!s) return;
  s->len = 0;
  if (s->data) {
    s->data[0] = '\0';
  }
}

bool ds_append(DString *s, const char *buf, size_t n) {
  if (!s || !buf) return false;
  if (n == 0) return true;

  size_t needed = s->len + n + 1; /* +1 for null */
  if (needed > s->cap) {
    if (!ds__grow(s, needed)) return false;
  }

  memcpy(s->data + s->len, buf, n);
  s->len += n;
  s->data[s->len] = '\0';
  return true;
}

bool ds_append_cstr(DString *s, const char *cstr) {
  if (!cstr) return false;
  return ds_append(s, cstr, strlen(cstr));
}

bool ds_append_char(DString *s, char c) {
  return ds_append(s, &c, 1);
}

#endif /* DSTRING_IMPLEMENTATION */
