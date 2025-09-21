#ifndef COMPILER_H_
#define COMPILER_H_

#include "simplex.h"
#include "types.h"

enum VC_Puncts {
  VC_none_Punct,
  VC_error_Punct,
  VC_Add_Punct,
  VC_Eq_Punct,
  VC_Assign_Punct,
  VC_Sub_Punct,
  VC_Mod_Punct,
  VC_Div_Punct,
  VC_Mult_Punct,
  VC_Ptr_Punct,
  VC_PP_Punct,
  VC_MM_Punct,
  VC_Less_Punct,
  VC_Gr_Punct,
};

enum VC_Kws {
  VC_none_Kw,
  VC_Let_Kw,
  VC_While_Kw,
  VC_If_Kw,
  VC_Fn_Kw,
  VC_Struct_Kw,
};

int prepass(lexer_t *l);
int main_pass(lexer_t *l, bool skip);

#endif
