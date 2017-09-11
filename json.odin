      import "core:fmt.odin";
      import "core:mem.odin";
using import "core:strconv.odin";

using import "leksa.odin";
using import "utileco.odin";

// @ref: https://bitbucket.org/WAHa_06x36/smalljsonparser/src/971a25326cb1?at=default
// @ref: http://json.org/

Token :: enum int {
    Null = 1,
       
    True,
    False,

    String,
    Float,
    Integer,

    Start_Array,
    End_Array,

    Start_Object,
    End_Object,

    Pair,

    Comma,
}

Error :: enum int {
    Unexpected_EOF        = -1,
    Unexpected_Line_Break = -2,
    Double_Radix          = -3,
}

read_null :: proc(lexer: ^Lexer) -> int {
    if              peek(lexer) == 'n' do
        if          next(lexer) == 'u' do
            if      next(lexer) == 'l' do
                if  next(lexer) == 'l' {
                    next(lexer);
                    return cast(int) Token.Null;
                }
    return 0;
}

read_bool :: proc(lexer: ^Lexer) -> int {
    if              peek(lexer) == 't' {
        if          next(lexer) == 'r' {
            if      next(lexer) == 'u' {
                if  next(lexer) == 'e' {
                    next(lexer);
                    return cast(int) Token.True;
                }
            }
        }
    } else if           peek(lexer) == 'f' {
        if              next(lexer) == 'a' {
            if          next(lexer) == 'l' {
                if      next(lexer) == 's' {
                    if  next(lexer) == 'e' {
                        next(lexer);
                        return cast(int) Token.False;
                    }
                }
            }
        }
    }

    return 0;
}

read_string :: proc(lexer: ^Lexer) -> int {
    // @todo: handle escaped characters

    if peek(lexer) != '"' do
        return 0;

    for {
        match next(lexer) {
        case '"':
            next(lexer);
            return cast(int) Token.String;
        
        case '\x00':
            return cast(int) Error.Unexpected_EOF;

        case '\r': fallthrough;
        case '\n':
            return cast(int) Error.Unexpected_Line_Break;
        }
    }

    // @note: should I put a length limit?
    // this could go on for quite a while
    // if someone forgets a closing quote
    assert(false, "unreachable code");
    return 0;
}

read_number :: proc(lexer: ^Lexer) -> int {
    // @todo: e+/- notation
    radix := false;

    char := peek(lexer);

    if !is_digit(char) && char != '-' do
        return 0;

    for ;; char = next(lexer) do
        if char == '.' do
            if radix do
                return cast(int) Error.Double_Radix;
            else do
                radix = true;
        else if !is_digit(char) do
            break;
    
    return radix ? cast(int) Token.Float : cast(int) Token.Integer;
}

read_symbol :: proc(lexer: ^Lexer) -> int {
    match peek(lexer) {
    case '[': 
        next(lexer);
        return cast(int) Token.Start_Array;
    case ']': 
        next(lexer);
        return cast(int) Token.End_Array;
    case '{': 
        next(lexer);
        return cast(int) Token.Start_Object;
    case '}': 
        next(lexer);
        return cast(int) Token.End_Object;
    case ':': 
        next(lexer);
        return cast(int) Token.Pair;
    case ',': 
        next(lexer);
        return cast(int) Token.Comma;
    }

    return 0;
}

eat_whitespace :: proc(lexer: ^Lexer) {
    for char := peek(lexer);; char = next(lexer) {
        match char {
        case ' ':  //
        case '\t': // do nothing.
        case '\v': //

        case '\r':
            tmp := swap_cursor(lexer, lexer.cursor);
            if next(lexer) != '\n' do
                line_break(lexer);
            swap_cursor(lexer, tmp);

        case '\n': line_break(lexer);

        case: return;
        }
    }
}

// @todo: import "leksa.odin" instead to avoid name collision
get_next :: proc(lexer: ^Lexer) -> (Lexeme, int) #inline {
    lex: Lexeme;
    i:   int;

    eat_whitespace(lexer);
    
    if lex, i = read(lexer, read_symbol); i != 0 do return lex, i;
    if lex, i = read(lexer, read_string); i != 0 do return lex, i;
    if lex, i = read(lexer, read_number); i != 0 do return lex, i;
    if lex, i = read(lexer, read_bool);   i != 0 do return lex, i;
    if lex, i = read(lexer, read_null);   i != 0 do return lex, i;
    
    return lex, i;
}

expect :: proc(lexer: ^Lexer, tokens: ...Token) -> (Lexeme, bool) #inline {
    lexeme, n := get_next(lexer);

    for token in tokens do if n == cast(int) token do return lexeme, true;

    swap_cursor(lexer, lexeme.cursor);

    match {
    case n > 0: fmt.printf("Expected `%v`; got `%v`.\r\n", tokens, cast(Token) n);
    case n < 0: fmt.printf("Expected `%v`; got `%v`.\r\n", tokens, cast(Error) n);
    case:       fmt.printf("Expected `%v`; got something totally wack.\r\n", tokens); // @todo: better error message
    }

    return lexeme, false;
}

consume :: proc(lexer: ^Lexer, tokens: ...Token) -> bool #inline {
    cursor := swap_cursor(lexer, lexer.cursor);

    _, n := get_next(lexer);

    for token in tokens do if n == cast(int) token do return true;

    swap_cursor(lexer, cursor);

    return false;
}

// @todo: name-type matching version (json string matches field) instead of order-type matching
_parse_inner :: proc(lexer: ^Lexer, type_info: ^Type_Info, data: rawptr) -> bool {
    type_info = type_info_base_without_enum(type_info);
    type_info = type_info_base_without_enum(type_info);
    // @todo: this is a hack, write a simple function to recurse to the basest base
        
    if consume(lexer, Token.Null) {
        mem.set(data, 0, type_info.size);
        return true;
    }

    match v in type_info.variant {
    case Type_Info.Struct:
        if _, ok := expect(lexer, Token.Start_Object); !ok do return false; // @error

        for t, i in v.types {
            if i != 0 && !consume(lexer, Token.Comma) do return false; // @error

            if _, ok := expect(lexer, Token.String); !ok do return false; // @error
            if _, ok := expect(lexer, Token.Pair);   !ok do return false; // @error
                
            if !_parse_inner(lexer, t, cast(^u8) data + v.offsets[i]) do return false; // @error
        }

        if consume(lexer, Token.Comma) && false do return false; // @error

        if _, ok := expect(lexer, Token.End_Object); !ok do return false; // @error

    case Type_Info.Pointer:
        ptr := alloc(v.elem.size);

        if !_parse_inner(lexer, v.elem, ptr) do return false; // @error
        
        mem.copy(data, &ptr, type_info.size); // @note: wonky?

    case Type_Info.Any:
        //ptr := alloc(v.elem.size);
        return false;
        // @todo: fuuuuuuuuuuuuuuuuuuuuuuuu
        // this can be anything so I can't pass a `^Type_Info`
        // I'll have to use largest size for numbers and use a new
        // proc that bases the size on the json instead of the odin
        //mem.copy(data, &ptr, type_info.size);

    case Type_Info.String:
        lexeme: Lexeme;
        ok:     bool;

        if lexeme, ok = expect(lexer, Token.String); !ok do return false; // @error

        value := clone_string(lexeme.text);
        mem.copy(data, &value, type_info.size);

    case Type_Info.Integer:
        lexeme: Lexeme;
        ok:     bool;

        if lexeme, ok = expect(lexer, Token.Integer); !ok do return false; // @error

        _value := parse_i128(lexeme.text);

        match type_info.size {
        case 16: mem.copy(data, &_value, type_info.size); 

        case 8:
            value := cast(i64) _value;
            mem.copy(data, &value, type_info.size);
        
        case 4:
            value := cast(i32) _value;
            mem.copy(data, &value, type_info.size); 
        
        case 2:
            value := cast(i16) _value;
            mem.copy(data, &value, type_info.size); 
        
        case 1:
            value := cast(i8) _value;
            mem.copy(data, &value, type_info.size); 
        
        case: return false; // @error
        }

    case Type_Info.Float:
        lexeme: Lexeme;
        ok:     bool;

        if lexeme, ok = expect(lexer, Token.Float); !ok do return false; // @error

        _value := parse_f64(lexeme.text);

        match type_info.size {
        case 8: mem.copy(data, &_value, type_info.size);
        
        case 4: 
            value := cast(f32) _value;
            mem.copy(data, &value, type_info.size);

        case: return false; // @error
        }

    case Type_Info.Boolean:
        lexeme: Lexeme;
        ok:     bool;
        
        value: bool;

        if consume(lexer, Token.True) {
            value = true;
            mem.copy(data, &value, type_info.size);
        } else if consume(lexer, Token.False) {
            mem.copy(data, &value, type_info.size);
        } else do return false; // @error

    case Type_Info.Array:
        if !consume(lexer, Token.Start_Array) do return false; // @error

        for i in 0..v.count {
            if i != 0 && !consume(lexer, Token.Comma) do return false; // @error

            if !_parse_inner(lexer, v.elem, cast(^u8) data + v.elem_size * i) do return false; // @error
        }

        if consume(lexer, Token.Comma) && false do return false; // @error: also, replace false with a flag

        if !consume(lexer, Token.End_Array) do return false; // @error
    
    case Type_Info.Vector:
        if !consume(lexer, Token.Start_Array) do return false; // @error

        for i in 0..v.count {
            if i != 0 && !consume(lexer, Token.Comma) do return false; // @error

            if !_parse_inner(lexer, v.elem, cast(^u8) data + v.elem_size * i) do return false; // @error
        }

        if consume(lexer, Token.Comma) && false do return false; // @error: also, replace false with a flag

        if !consume(lexer, Token.End_Array) do return false; // @error

    case Type_Info.Slice:
        //if !expect(lexer, Token.Start_Array) do return false; // @error

        return false;
        // @todo: implement

        //if !expect(lexer, Token.End_Array) do return false; // @error

    case Type_Info.Dynamic_Array:
        //if !expect(lexer, Token.Start_Array) do return false; // @error

        return false;
        // @todo: implement

        //if !expect(lexer, Token.End_Array) do return false; // @error

    // @todo: Type_Info.Enum      (should already work)
    // @todo: Type_Info.Map       (same as struct?)
    // @todo: Type_Info.Bit_Field (string!?)
    // @todo: Type_Info.Complex   (string?)
    // @todo: Type_Info.Rune      (need to unescape strings first to get one char)

    case: return false; // @error
    }

    return true;
}

parse :: proc(T: type, json: string) -> T #inline {
    result: T;

    lexer := make_lexer(json);

    if _parse_inner(&result, &lexer) do
        return result, true;
    
    return result, false;
}

parse_file :: proc(T: type, path: string) -> (T, bool) #inline {
    result: T;

    lexer, ok := load_lexer(path);
    if !ok do return result, false;

    if _parse_inner(&lexer, type_info_of(T), &result) do
        return result, true;
    
    return result, false;
}

some_number := 0157983579845
