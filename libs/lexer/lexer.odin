package lexer
// v0.3.1
// - v0.3.1 changelog:
// -- get_token() now returns a bool to indicate if it reached the EOF
// - v0.3 changelog:
// -- use punct token_id and put the char/punt in intlit
// -- added custom bases for numbers ex: 12#AAA
// -- added more error checking for number parsing
// - v0.2 changelog:
// -- added check_type
// -- added the ascii character for most token_ids
// -- init_lexer now handles errors
// -- fixed l.col and l.row sometimes not being correct
// -- added a row and col and file to token


import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"

token_id :: enum {
  none,
  punct,
  either_end_or_failure,
  intlit,
  charlit,
  floatlit,
  id,
  dqstring,
  sqstring,
  eq,
  notq,
  lesseq,
  greatereq,
  andand,
  oror,
  shl,
  shr,
  plusplus,
  minusminus,
  pluseq,
  minuseq,
  multeq,
  diveq,
  modeq,
  andeq,
  oreq,
  xoreq,
  arrow,
  eqarrow,
  shleq,
  shreq,
}

lexer :: struct {
  file:     string,
  content: []u8,
  cursor:  uint,
  token:   token,
  row:     uint,
  col:     uint,
}

token :: struct {
  type:     token_id,
  intlit:   i64,
  floatlit: f64,
  str:      string,
  file:     string,
  row:      uint,
  col:      uint,
}

string_to_u8 :: proc(s: ^string) -> Maybe([]u8) {
  return slice.from_ptr(cast(^u8)strings.clone_to_cstring(s^), len(s))
}

check_type :: proc(l: ^lexer, expected: token_id, prt: bool = true) -> bool {
  if l.token.type != expected && prt {
    fmt.eprintfln(
      "%s:%d:%d expected {} but got {}",
      l.token.file,
      l.token.row + 1,
      l.col,
      expected,
      l.token.type,
    )
  }
  return l.token.type == expected
}


init_lexer :: proc(file: string) -> lexer {
  l: lexer
  l.file = file
  l.token.file = file

  str, err := read_file(file)
  if err != nil {
    fmt.eprintfln("could not open file %s, because {}", file, err)
  }
  str, _ = strings.replace_all(str, "\r\n", "\n")
  l.content, _ = string_to_u8(&str).?
  if len(l.content) == 0 {
    fmt.println("file", file, "is empty")
    os.exit(1)
  }
  delete(str)

  return l
}

get_token :: proc(l: ^lexer) -> bool {
  l.token.type = .none
  l.token.intlit = 0
  l.token.floatlit = 0
  l.token.str = ""

  if l.cursor == len(l.content) {
    l.token.type = .either_end_or_failure
    return false
  }

  for l.content[l.cursor] == ' ' || l.content[l.cursor] == '\t' {
    l.cursor += 1
    l.col += 1
  }

  if b, ok := (peek_at_index(l.content, l.cursor + 1)).?;
     ok == true && l.content[l.cursor] == '/' && b == '/' {
    l.cursor += 1
    for l.cursor < len(l.content) && l.content[l.cursor] != '\n' {
      l.cursor += 1
      l.col += 1
    }
   
    return get_token(l)
  }

  if is_alphabetical(l.content[l.cursor]) {
    s := l.cursor

    l.token.col = l.col
    l.token.row = l.row + 1

    l.cursor += 1
    for l.cursor < len(l.content) && is_alphanumerical(l.content[l.cursor]) do l.cursor += 1
    l.token.str = (string(l.content[s:l.cursor]))
    l.token.type = .id
    l.col += l.cursor - s
  } else if b, ok := peek_at_index(l.content, l.cursor + 1).?;
     is_numerical(l.content[l.cursor]) || (ok && l.content[l.cursor] == '-' && is_numerical(b)) {
    
    digits: []byte = {'1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F'}

    s := l.cursor
    base := 10
    l.token.col = l.col
    l.token.row = l.row + 1

    l.cursor += 1
    for l.cursor < len(l.content) && (is_numerical(l.content[l.cursor]) || l.content[l.cursor] == '.') do l.cursor += 1

    if l.cursor < len(l.content) && (l.content[l.cursor] == 'x' || l.content[l.cursor] == 'o' || l.content[l.cursor] == 'b' || l.content[l.cursor] == '#') {
      
      switch l.content[l.cursor] {
      case 'b': base    = 2
      case 'o': base    = 8
      case 'x': base    = 16
      case '#': base, _ = strconv.parse_int(string(l.content[s:l.cursor]))
      }
      
      if base > 16 || base < 1 {
        fmt.eprintfln("%s:%d:%d ERROR: base must be between 1-16", l.file, l.token.row, l.token.col)
        os.exit(1)
      }

      l.cursor += 1
      s = l.cursor

      for l.cursor < len(l.content) && is_alphanumerical(l.content[l.cursor]) do l.cursor += 1
    }
    ok: bool
    if strings.contains(string(l.content[s:l.cursor]), ".") {
      l.token.type = .floatlit
      l.token.floatlit, ok = strconv.parse_f64(string(l.content[s:l.cursor]))
      if !ok {
        fmt.eprintfln("there was an error parsing the the number '%s'", string(l.content[s:l.cursor]))
        os.exit(1)
      }
    } else {
      l.token.type = .intlit
      if l.token.intlit, ok = strconv.parse_i64_of_base(string(l.content[s:l.cursor]), base, auto_cast &l.token.intlit); !ok {
        fmt.eprintfln("there was an error parsing the the number '%s' in the base '%d', max valid digit is '%c'", string(l.content[s:l.cursor]), base, digits[base - 2])
        os.exit(1)
      }
    }
    l.col += l.cursor - s

  } else if l.content[l.cursor] == '\n' {
    l.row += 1
    l.col = 0
    l.cursor += 1
    
    return get_token(l)
  } else if l.content[l.cursor] == '\'' {
    l.cursor += 1
    l.token.type = .sqstring

    l.token.col = l.col
    l.token.row = l.row + 1

    s := l.cursor
    for l.cursor < len(l.content) && l.content[l.cursor] != '\'' {
      if l.content[l.cursor] == '\\' do l.cursor += 1
      l.cursor += 1
    }
    l.col += l.cursor - s + 2

    if l.cursor - s == 1 {
      l.token.intlit = auto_cast l.content[s]
      l.token.type = .charlit
    } else {
      l.token.str = string(l.content[s:l.cursor])
    }
    l.cursor += 1
  } else if l.content[l.cursor] == '"' {
    l.cursor += 1
    l.token.type = .dqstring

    l.token.col = l.col
    l.token.row = l.row + 1

    s := l.cursor
    for l.cursor < len(l.content) && l.content[l.cursor] != '"' {
      if l.content[l.cursor] == '\\' do l.cursor += 1
      l.cursor += 1
    }
    l.col += l.cursor - s + 2
    l.token.str = string(l.content[s:l.cursor])
    l.cursor += 1
  } else if b, ok := (peek_at_index(l.content, l.cursor + 1)).?; ok == true {
    if l.content[l.cursor] == '=' && b == '=' {

      l.token.col = l.col
      l.token.row = l.row + 1

      l.token.type = .eq
      l.col += 2
      l.cursor += 2
    } else if l.content[l.cursor] == '<' && b == '=' {

      l.token.col = l.col
      l.token.row = l.row + 1

      l.token.type = .lesseq
      l.col += 2
      l.cursor += 2
    } else if l.content[l.cursor] == '>' && b == '=' {
      l.token.type = .greatereq

      l.token.col = l.col
      l.token.row = l.row + 1

      l.col += 2
      l.cursor += 2
    } else if l.content[l.cursor] == '+' && b == '=' {
      l.token.type = .pluseq

      l.token.col = l.col
      l.token.row = l.row + 1

      l.col += 2
      l.cursor += 2
    } else if l.content[l.cursor] == '-' && b == '=' {
      l.token.type = .minuseq

      l.token.col = l.col
      l.token.row = l.row + 1

      l.col += 2
      l.cursor += 2
    } else if l.content[l.cursor] == '/' && b == '=' {
      l.token.type = .diveq

      l.token.col = l.col
      l.token.row = l.row + 1

      l.col += 2
      l.cursor += 2
    } else if l.content[l.cursor] == '*' && b == '=' {
      l.token.type = .multeq

      l.token.col = l.col
      l.token.row = l.row + 1

      l.col += 2
      l.cursor += 2
    } else if l.content[l.cursor] == '%' && b == '=' {
      l.token.type = .modeq

      l.token.col = l.col
      l.token.row = l.row + 1

      l.col += 2
      l.cursor += 2
    } else if l.content[l.cursor] == '&' && b == '=' {
      l.token.type = .andeq

      l.token.col = l.col
      l.token.row = l.row + 1

      l.col += 2
      l.cursor += 2
    } else if l.content[l.cursor] == '|' && b == '=' {
      l.token.type = .oreq

      l.token.col = l.col
      l.token.row = l.row + 1

      l.col += 2
      l.cursor += 2
    } else if l.content[l.cursor] == '^' && b == '=' {
      l.token.type = .xoreq

      l.token.col = l.col
      l.token.row = l.row + 1

      l.col += 2
      l.cursor += 2
    } else if l.content[l.cursor] == '-' && b == '>' {
      l.token.type = .arrow

      l.token.col = l.col
      l.token.row = l.row + 1

      l.col += 2
      l.cursor += 2
    } else if l.content[l.cursor] == '=' && b == '>' {
      l.token.type = .eqarrow

      l.token.col = l.col
      l.token.row = l.row + 1

      l.col += 2
      l.cursor += 2
    } else if l.content[l.cursor] == '!' && b == '=' {
      l.token.type = .notq

      l.token.col = l.col
      l.token.row = l.row + 1

      l.col += 2
      l.cursor += 2
    } else if l.content[l.cursor] == '&' && b == '&' {
      l.token.type = .andand

      l.token.col = l.col
      l.token.row = l.row + 1

      l.col += 2
      l.cursor += 2
    } else if l.content[l.cursor] == '|' && b == '|' {
      l.token.type = .oror

      l.token.col = l.col
      l.token.row = l.row + 1

      l.col += 2
      l.cursor += 2
    } else if l.content[l.cursor] == '+' && b == '+' {
      l.token.type = .plusplus

      l.token.col = l.col
      l.token.row = l.row + 1

      l.col += 2
      l.cursor += 2
    } else if l.content[l.cursor] == '-' && b == '-' {
      l.token.type = .minusminus

      l.token.col = l.col
      l.token.row = l.row + 1

      l.col += 2
      l.cursor += 2
    } else if l.content[l.cursor] == '<' && b == '<' {
      l.token.type = .shl

      l.token.col = l.col
      l.token.row = l.row + 1

      l.col += 2
      l.cursor += 1
      a, ok2 := peek_at_index(l.content, l.cursor + 1).?
      if ok2 && a == '=' {
        l.token.type = .shleq
        l.col += 1
        l.cursor += 1
      }
      l.cursor += 1
    } else if l.content[l.cursor] == '>' && b == '>' {
      l.token.type = .shr

      l.token.col = l.col
      l.token.row = l.row + 1

      l.col += 2
      l.cursor += 1
      a, ok2 := peek_at_index(l.content, l.cursor + 1).?
      if ok2 && a == '=' {
        l.token.type = .shreq
        l.col += 1
        l.cursor += 1
      }
      l.cursor += 1
    } else {
      l.token.intlit = auto_cast l.content[l.cursor]
      l.token.type = .punct
      l.token.col = l.col
      l.token.row = l.row + 1
      l.cursor += 1
      l.col += 1
    }
  } else {
    l.token.intlit = auto_cast l.content[l.cursor]
    l.token.type = .punct
    l.token.col = l.col
    l.token.row = l.row + 1
    l.cursor += 1
    l.col += 1
  }

  return true
}

peek_at_index :: proc(l: []u8, index: uint) -> Maybe(byte) {
  if index >= len(l) do return nil
  return l[index]
}

read_file :: proc(file: string) -> (res: string, err: os.Error) {
  file, ferr := os.open(file)
  if ferr != nil {
    return "", ferr
  }
  defer os.close(file)

  buff_size, _ := os.file_size(file)
  buf := make([]byte, buff_size)
  for {
    n, _ := os.read(file, buf)
    if n == 0 do break
  }

  return string(buf), nil
}

is_whitespace :: proc(c: byte) -> bool {
  return c == ' ' || c == '\t' || c == '\r'
}

is_numerical :: proc(c: byte) -> bool {
  return c >= '0' && c <= '9'
}

is_alphabetical :: proc(c: byte) -> bool {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

is_hex_numerical :: proc(c: byte) -> bool {
  cc := c
  if c <= 'z' && c >= 'a' do cc -= 32
  return is_numerical(cc) || (cc <= 'F' && cc >= 'A')
}

is_binary_numerical :: proc(c: byte) -> bool {
  return c == '0' || c == '1'
}

is_octal_numerical :: proc(c: byte) -> bool {
  return c >= '0' && c <= '7'
}

is_alphanumerical :: proc(c: byte) -> bool {
  return is_numerical(c) || is_alphabetical(c) || c == '_'
}