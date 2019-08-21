package json

import "core:fmt"
import "core:mem"
import "core:os"
import "core:runtime"
import "core:strconv"
import "core:strings"
import "core:unicode/utf16"
import "core:unicode/utf8"

import "shared:path"


DEBUG :: true;


////////////////////////////
//
// GENERAL
////////////////////////////

escape_string :: proc(str: string) -> (string, bool) #no_bounds_check {
    buf: strings.Builder;

    for i := 0; i < len(str); {
        char, skip := inline utf8.decode_rune(([]u8)(str[i:]));
        i += skip;

        switch char {
        case: 
            if inline utf8.valid_rune(char) {
                inline strings.write_rune(&buf, char);
            }
            else {
                strings.destroy_builder(&buf);
                return "", false;
            }

        case '"':  inline fmt.sbprint(&buf, "\\\"");
        //case '\'': inline fmt.sbprint(&buf, "\\'");
        case '\\': inline fmt.sbprint(&buf, "\\\\");
        case '\a': inline fmt.sbprint(&buf, "\\a");
        case '\b': inline fmt.sbprint(&buf, "\\b");
        case '\f': inline fmt.sbprint(&buf, "\\f");
        case '\n': inline fmt.sbprint(&buf, "\\n");
        case '\r': inline fmt.sbprint(&buf, "\\r");
        case '\t': inline fmt.sbprint(&buf, "\\t");
        case '\v': inline fmt.sbprint(&buf, "\\v");
        }
    }

    return inline strings.to_string(buf), true;
}

unescape_string :: proc(str: string) -> (string, bool) #no_bounds_check {
    buf: strings.Builder;

    for i := 0; i < len(str); {
        char, skip := inline utf8.decode_rune(([]u8)(str[i:]));
        i += skip;

        switch char {
        case: inline strings.write_rune(&buf, char);

        case '"': // @note: do nothing.

        case '\\':
            char, skip = inline utf8.decode_rune(([]u8)(str[i:]));
            i += skip;

            switch char {
            case '\\': inline strings.write_rune(&buf, '\\');
            case '\'': inline strings.write_rune(&buf, '\'');
            case '"':  inline strings.write_rune(&buf, '"');

            case 'a': inline strings.write_rune(&buf, '\a');
            case 'b': inline strings.write_rune(&buf, '\b');
            case 'f': inline strings.write_rune(&buf, '\f');
            case 'n': inline strings.write_rune(&buf, '\n');
            case 'r': inline strings.write_rune(&buf, '\r');
            case 't': inline strings.write_rune(&buf, '\t');
            case 'v': inline strings.write_rune(&buf, '\v');

            case 'u':
                lo, hi: rune;
                hex := [?]u8{'0', 'x', '0', '0', '0', '0'};

                c0, s0 := inline utf8.decode_rune(([]u8)(str[i:])); hex[2] = (u8)(c0); i += s0;
                c1, s1 := inline utf8.decode_rune(([]u8)(str[i:])); hex[3] = (u8)(c1); i += s1;
                c2, s2 := inline utf8.decode_rune(([]u8)(str[i:])); hex[4] = (u8)(c2); i += s2;
                c3, s3 := inline utf8.decode_rune(([]u8)(str[i:])); hex[5] = (u8)(c3); i += s3;

                lo = rune(inline strconv.parse_int(string(hex[:])));

                if inline utf16.is_surrogate(lo) {
                    c0, s0 := inline utf8.decode_rune(([]u8)(str[i:])); i += s0;
                    c1, s1 := inline utf8.decode_rune(([]u8)(str[i:])); i += s1;

                    if c0 == '\\' && c1 == 'u' {
                        c0, s0 = inline utf8.decode_rune(([]u8)(str[i:])); hex[2] = (u8)(c0); i += s0;
                        c1, s1 = inline utf8.decode_rune(([]u8)(str[i:])); hex[3] = (u8)(c1); i += s1;
                        c2, s2 = inline utf8.decode_rune(([]u8)(str[i:])); hex[4] = (u8)(c2); i += s2;
                        c3, s3 = inline utf8.decode_rune(([]u8)(str[i:])); hex[5] = (u8)(c3); i += s3;                      

                        hi = rune(inline strconv.parse_u64(string(hex[:])));
                        lo = inline utf16.decode_surrogate_pair(lo, hi);

                        if lo == utf16.REPLACEMENT_CHAR {
                            return "", false;
                        }
                    } else {
                        return "", false;
                    }
                }

                inline strings.write_rune(&buf, lo);

            case: return "", false;
            }
        }
    }

    return inline strings.to_string(buf), true;
}

error :: proc{lexer_error, parser_error};



////////////////////////////
//
// TYPES
////////////////////////////

Value :: union {
    i64,
    f64,
    bool,
    string,
    []Value,
    map[string]Value,
}

Token :: struct {
    using pos: Pos,
    kind: Kind,
    text: string,
}

using Kind :: enum {
    INVALID,

    NULL,
    TRUE,
    FALSE,
    
    FLOAT,
    INT,
    STRING,

    COLON,
    COMMA,
    
    OPEN_BRACE,
    CLOSE_BRACE,

    OPEN_BRACKET,
    CLOSE_BRACKET,

    END,
}

Pos :: struct {
    index: int,
    lines: int,
    chars: int,
}

destroy :: proc(value: Value, allocator := context.allocator) {
    switch v in value {
    case map[string]Value:
        for key, val in v {
            delete(key, allocator);
            destroy(val, allocator);
        }
        delete(v);
    case []Value:
        for val in v {
            destroy(val, allocator);
        }
        delete(v, allocator);
    case string:
        delete(v, allocator);
    }
}



///////////////////////////
//
// LEXER
///////////////////////////

EOF :: utf8.RUNE_EOF;
EOB :: '\x00';

Lexer :: struct {
    using pos: Pos,
    path:   string,
    source: string,
    char:   rune,
    skip:   int,
    errors: int,
}

lexer_error :: inline proc(using lexer : ^Lexer, format: string, args: ..any, loc := #caller_location) {
    fmt.printf_err("%s(%d:%d) Lexing error: %s\n", path, lines, chars, fmt.tprintf(format, ..args));

    when #defined(DEBUG) {
        fmt.printf_err("    %s(%d:%d): %s\n", loc.file_path, loc.line, loc.column, loc.procedure);
    }

    errors += 1;
}

next_char :: inline proc"contextless"(using lexer: ^Lexer) -> rune #no_bounds_check {
    index += skip;
    chars += 1;

    //char, skip = inline utf8.decode_rune(([]u8)(source[index:]));
    char = index < len(source) ? rune(source[index]) : EOB;
    skip = 1;

    return char;
}

lex :: proc(text: string, filename := "") -> []Token #no_bounds_check {
    using lexer := Lexer {
        pos    = Pos{lines=1},
        path   = filename,
        source = text,
    };

    tokens := make([dynamic]Token, 0, len(text) / 5); // @todo(bp): dial in

    next_char(&lexer);

    loop: for {
        token := Token{pos, ---, ---};

        switch char {
        case 'n':
            if next_char(&lexer) == 'u' &&
               next_char(&lexer) == 'l' &&
               next_char(&lexer) == 'l' {
                token.kind = NULL;
                next_char(&lexer);
            } else {
                error(&lexer, "Invalid identifier; expected 'null'");
            }
        
        case 't':
            if next_char(&lexer) == 'r' &&
               next_char(&lexer) == 'u' &&
               next_char(&lexer) == 'e' {
                token.kind = TRUE;
                next_char(&lexer);
            } else {
                error(&lexer, "Invalid identifier; expected 'true'");
            }
        
        case 'f':
            if next_char(&lexer) == 'a' &&
               next_char(&lexer) == 'l' &&
               next_char(&lexer) == 's' &&
               next_char(&lexer) == 'e' {
                token.kind = FALSE;
                next_char(&lexer);
            } else {
                error(&lexer, "Invalid identifier; expected 'false'");
            }

        case '+', '-':
            switch next_char(&lexer) {
            case '0'..'9': // continue
            case:          // @todo(bp): wut
            }
            fallthrough;

        case '0'..'9':
            token.kind = INT;

            for {
                switch next_char(&lexer) {
                case '0'..'9': continue;
                case '.':
                    if token.kind == FLOAT {
                        error(&lexer, "Double radix in float");
                    } else {
                        token.kind = FLOAT;
                    }
                    continue;
                }

                break;
            }

        case '"':
            token.kind = STRING;

            // @todo(bpunsky): proper string parsing? or just handle when converting to a value?

            esc := false;

            for {
                switch next_char(&lexer) {
                case '\\':
                    esc = !esc;
                    continue;
                
                case '"':
                    if esc {
                        esc = false;
                        continue;
                    } else {
                        next_char(&lexer);
                    }
                
                case:
                    if esc do esc = false;
                    continue;
                }

                break;
            }

        case ',':
            token.kind = COMMA;
            next_char(&lexer);

        case ':':
            token.kind = COLON;
            next_char(&lexer);

        case '{':
            token.kind = OPEN_BRACE;
            next_char(&lexer);

        case '}':
            token.kind = CLOSE_BRACE;
            next_char(&lexer);

        case '[':
            token.kind = OPEN_BRACKET;
            next_char(&lexer);

        case ']':
            token.kind = CLOSE_BRACKET;
            next_char(&lexer);

        case ' ', '\t':
            next_char(&lexer);
            continue;

        case '\r':
            if next_char(&lexer) == '\n' {
                next_char(&lexer);
            }
            lines += 1;
            chars  = 1;
            continue;

        case '\n':
            next_char(&lexer);
            lines += 1;
            chars  = 1;
            continue;

        case EOB, EOF, utf8.RUNE_ERROR:
            break loop; // @todo(bp): RUNE_ERROR seems sketchy

        case:
            error(&lexer, "Illegal rune '%v' (%x)", char, (int)(char));
            break loop;
        }

        token.text = source[token.index:index];
        inline append(&tokens, token);
    }

    if errors > 0 { // @note(bpunsky): triggers when opt > 0
        fmt.printf_err("%d errors\n", errors);
        delete(tokens);
        panic("Aborting..."); // @fix(bpunsky)
        return nil;
    }

    inline append(&tokens, Token{pos, END, ""});

    return tokens[:];
}



///////////////////////////
//
// PARSING
///////////////////////////

Parser :: struct {
    filename: string,
    source:   string,

    tokens: []Token,
    index:  int,

    errors: int,
}

parser_error :: proc(using parser: ^Parser, message: string, args: ..any, loc := #caller_location) {
    msg := fmt.aprintf(message, ..args);
    defer delete(msg);

    if index < len(tokens) {
        token := tokens[index];
        fmt.printf_err("%s(%d,%d) Error: %s\n", filename, token.lines, token.chars, msg);
    } else {
        fmt.printf_err("%s Error: %s\n", filename, msg);
    }

    when #defined(DEBUG) {
        fmt.printf_err("    %s(%d:%d): %s\n", loc.file_path, loc.line, loc.column, loc.procedure);
    }

    errors += 1;
}

allow :: inline proc(using parser: ^Parser, kinds: ..Kind) -> ^Token #no_bounds_check {
    if index >= len(tokens) do return nil;

    token := &tokens[index];

    for kind in kinds {
        if token.kind == kind {
            index += 1;
            return token;
        }
    }

    return nil;
}

expect :: inline proc(using parser: ^Parser, kinds: ..Kind, loc := #caller_location) -> ^Token {
    token := inline allow(parser, ..kinds);

    if token == nil {
        error(parser, "Expected %v; got %v", kinds, token.kind, loc);
    }

    return token;
}

skip :: proc(using parser: ^Parser, kinds: ..Kind) {
    for token := allow(parser, ..kinds); token != nil; token = allow(parser, ..kinds) {
        // continue
    }
}


parse_text :: inline proc(text: string, path := "") -> (Value, bool) {
    parser := Parser{
        filename = path,
        source   = text,
        tokens   = lex(text, path),
    };

    return parse(&parser);
}

parse_file :: inline proc(path: string) -> (Value, bool) {
    if bytes, ok := os.read_entire_file(path); ok {
        return parse_text(string(bytes), path);
    }

    return Value{}, false;
}


parse :: proc(using parser: ^Parser) -> (Value, bool) {
    token := expect(parser, OPEN_BRACE, OPEN_BRACKET, STRING, INT, FLOAT, TRUE, FALSE, NULL);

    if token == nil {
        return ---, false;
    }

    switch token.kind {
    case OPEN_BRACE:
        object: map[string]Value;

        if allow(parser, CLOSE_BRACE) != nil {
            return object, true;
        }

        for {
            key := expect(parser, STRING);
            if key == nil {
                destroy(object);
                return ---, false;
            }

            if expect(parser, COLON) == nil {
                destroy(object);
                return ---, false;
            }

            if value, ok := parse(parser); ok {
                if str, ok := unescape_string(key.text); ok {
                    object[str] = value;

                    if token := expect(parser, COMMA, CLOSE_BRACE); token != nil {
                        switch token.kind {
                        case COMMA:       continue;
                        case CLOSE_BRACE: break;
                        }
                        break;
                    } else {
                        destroy(object);
                        return ---, false;
                    }
                }
                else {
                    error(parser, "Failed to escape string");
                    destroy(object);
                    return ---, false;
                }
            }
            else {
                error(parser, "Expected an object value.");
                destroy(object);
                return ---, false;
            }
        }

        return object, true;

    case OPEN_BRACKET:
        array: [dynamic]Value;

        if allow(parser, CLOSE_BRACKET) != nil {
            return array[:], true;
        }

        for {
            if value, ok := parse(parser); ok {
                append(&array, value);

                if token := expect(parser, COMMA, CLOSE_BRACKET); token != nil {
                    switch token.kind {
                    case COMMA:         continue;
                    case CLOSE_BRACKET: break;
                    }
                    break;
                } else {
                    destroy(array[:]);
                    return ---, false;
                }
            }
            else {
                error(parser, "Expected an array element.");
                return ---, false;
            }
        }

        return array[:], true;

    case STRING: return unescape_string(token.text);
    case INT:    return strconv.parse_i64(token.text), true;
    case FLOAT:  return strconv.parse_f64(token.text), true;
    case TRUE:   return true, true;
    case FALSE:  return false, true;
    case NULL:   return nil, true;
    }

    // @todo(bp): nice shiny error message

    return ---, false;
}



///////////////////////////
//
// PRINTING
///////////////////////////

buffer_print :: proc(buf: ^strings.Builder, value: Value, indent := 0) {
    /*#complete*/ switch v in value {
    case map[string]Value:
        indent := indent;
        fmt.sbprint(buf, "{");

        if len(v) != 0 {
            fmt.sbprint(buf, "\n");
            indent += 1;

            i := 0;
            for key, value in v {
                for _ in 0..indent-1 do fmt.sbprint(buf, "    ");
     
                fmt.sbprint(buf, "\"");
                if str, ok := escape_string(key); ok {
                    fmt.sbprint(buf, str); // @todo: check for whitespace in JSON5
                }
                fmt.sbprint(buf, "\"");
     
                fmt.sbprint(buf, ": ");
     
                buffer_print(buf, value, indent);

                if i != len(v)-1 do fmt.sbprint(buf, ",");

                fmt.sbprintln(buf);

                i += 1;
            }

            indent -= 1;
            for _ in 0..indent-1 do fmt.sbprint(buf, "    ");
        }

        fmt.sbprint(buf, "}");

    case []Value:
        indent := indent;
        fmt.sbprint(buf, "[");

        if len(v) != 0 {
            fmt.sbprint(buf, "\n");
            indent += 1;
            
            for value, i in v {
                for _ in 0..indent-1 do fmt.sbprint(buf, "    ");

                buffer_print(buf, value, indent);

                if i != len(v)-1 do fmt.sbprint(buf, ",");

                fmt.sbprintln(buf);
            }
            
            indent -= 1;
            for _ in 0..indent-1 do fmt.sbprint(buf, "    ");
        }

        fmt.sbprint(buf, "]");

    case string:
        if str, ok := escape_string(v); ok {
            fmt.sbprintf(buf, "\"%s\"", str);
        }

    case bool: fmt.sbprint(buf, v);
    case f64:  fmt.sbprint(buf, v);
    case i64:  fmt.sbprint(buf, v);
    case:      fmt.sbprint(buf, "null");
    }
}

value_to_string :: inline proc(value: Value, allocator := context.allocator) -> string {
    buf := strings.make_builder(allocator);
    buffer_print(&buf, value);
    return strings.to_string(buf);
}

print_value :: inline proc(value: Value, allocator := context.temp_allocator) {
    json := value_to_string(value, allocator);
    defer delete(json);

    fmt.printf("\n%s\n\n", json);
}



///////////////////////////
//
// MARSHALLING
///////////////////////////

// @todo(bp): need a treeless, direct-to-string variant

marshal :: proc(data: any, allocator := context.allocator) -> (Value, bool) {
    type_info := runtime.type_info_base(type_info_of(data.id));

    switch v in type_info.variant {
    case runtime.Type_Info_Integer:
        value: i64;

        switch type_info.size {
        case 8: value = (i64)((^i64)(data.data)^);
        case 4: value = (i64)((^i32)(data.data)^);
        case 2: value = (i64)((^i16)(data.data)^);
        case 1: value = (i64)((^i8) (data.data)^);
        }

        return value, true;

    case runtime.Type_Info_Float:
        value: f64;

        switch type_info.size {
        case 8: value = (f64)((^f64)(data.data)^);
        case 4: value = (f64)((^f32)(data.data)^);
        }

        return value, true;

    case runtime.Type_Info_String:
        return strings.clone(data.(string)), true;

    case runtime.Type_Info_Boolean:
        return data.(bool), true;

    case runtime.Type_Info_Enum:
        for val, i in v.values {
            #complete switch vv in val {
            case rune:    if vv == (^rune)   (data.data)^ do return strings.clone(v.names[i]), true;
            case i8:      if vv == (^i8)     (data.data)^ do return strings.clone(v.names[i]), true;
            case i16:     if vv == (^i16)    (data.data)^ do return strings.clone(v.names[i]), true;
            case i32:     if vv == (^i32)    (data.data)^ do return strings.clone(v.names[i]), true;
            case i64:     if vv == (^i64)    (data.data)^ do return strings.clone(v.names[i]), true;
            case int:     if vv == (^int)    (data.data)^ do return strings.clone(v.names[i]), true;
            case u8:      if vv == (^u8)     (data.data)^ do return strings.clone(v.names[i]), true;
            case u16:     if vv == (^u16)    (data.data)^ do return strings.clone(v.names[i]), true;
            case u32:     if vv == (^u32)    (data.data)^ do return strings.clone(v.names[i]), true;
            case u64:     if vv == (^u64)    (data.data)^ do return strings.clone(v.names[i]), true;
            case uint:    if vv == (^uint)   (data.data)^ do return strings.clone(v.names[i]), true;
            case uintptr: if vv == (^uintptr)(data.data)^ do return strings.clone(v.names[i]), true;
            }
        }

    case runtime.Type_Info_Array:
        array := make([dynamic]Value, 0, v.count, allocator);

        for i in 0..<v.count {
            if tmp, ok := marshal(any{rawptr(uintptr(data.data) + uintptr(v.elem_size*i)), v.elem.id}, allocator); ok {
                append(&array, tmp);
            } else {
                // @todo(bp): error
                return nil, false;
            }
        }
        
        return array[:], true;

    case runtime.Type_Info_Slice:
        a := cast(^mem.Raw_Slice) data.data;

        array := make([dynamic]Value, 0, a.len, allocator);

        for i in 0..<a.len {
            if tmp, ok := marshal(any{rawptr(uintptr(a.data) + uintptr(v.elem_size*i)), v.elem.id}, allocator); ok {
                append(&array, tmp);
            } else {
                // @todo(bp): error
                return nil, false;
            }
        }

        return array[:], true;

    case runtime.Type_Info_Dynamic_Array:
        a := cast(^mem.Raw_Dynamic_Array) data.data;

        array := make([dynamic]Value, 0, a.len, allocator);

        for i in 0..<a.len {
            if tmp, ok := marshal(transmute(any) any{rawptr(uintptr(a.data) + uintptr(v.elem_size*i)), v.elem.id}, allocator); ok {
                append(&array, tmp);
            } else {
                // @todo(bp): error
                return nil, false;
            }
        }

        return array[:], true;

    case runtime.Type_Info_Struct:
        object := make(map[string]Value, 16, allocator);

        for ti, i in v.types {
            if tmp, ok := marshal(any{rawptr(uintptr(data.data) + uintptr(v.offsets[i])), ti.id}, allocator); ok {
                object[strings.clone(v.names[i])] = tmp;
            } else {
                // @todo(bp): error
                return nil, false;
            }
        }

        return object, true;

    case runtime.Type_Info_Map:
        // @todo: implement. ask bill about this, maps are fucky
        return nil, false;
    }

    return nil, false;
}

marshal_string :: inline proc(data: any, allocator := context.allocator) -> (string, bool) {
    if value, ok := marshal(data); ok {
        defer destroy(value);

        return value_to_string(value, allocator), true;
    }

    return "", false;
}

marshal_file :: inline proc(path: string, data: any, allocator := context.allocator) -> bool {
    if str, ok := inline marshal_string(data, allocator); ok {
        defer delete(str, allocator);

        return os.write_entire_file(path, ([]u8)(str));
    }

    return false;
}



///////////////////////////
//
// UNMARSHALLING
///////////////////////////

// @note(bp): don't pass uninitialized values to the unmarshal_*_any variants!

unmarshal :: proc{unmarshal_value_to_any, unmarshal_value_to_type};

unmarshal_value_to_any :: proc(data: any, value: Value, allocator := context.allocator) -> bool {
    type_info := runtime.type_info_base(type_info_of(data.id));

    // @todo(bp): now that unmarshal takes an allocator, handle pointers!

    switch v in value {
    case map[string]Value:
        switch variant in type_info.variant {
        case runtime.Type_Info_Struct:
            for field, i in variant.names {
                // @todo: stricter type checking and by-order instead of by-name as an option
                a := any{rawptr(uintptr(data.data) + uintptr(variant.offsets[i])), variant.types[i].id};
                if !unmarshal(a, v[field], allocator) do return false; // @error
            }

            return true; 
        
        case runtime.Type_Info_Map:
            // @todo: implement. ask bill about this, maps are a daunting prospect because they're fairly opaque
        }

    case []Value:
        switch variant in type_info.variant {
        case runtime.Type_Info_Array:
            if len(v) > variant.count {
                fmt.println_err("Too many elements to fit array");
                return false; // @error
            }

            for i in 0..<variant.count {
                a := any{rawptr(uintptr(data.data) + uintptr(variant.elem_size * i)), variant.elem.id};
                if !unmarshal(a, v[i], allocator) do return false; // @error
            }

            return true;

        case runtime.Type_Info_Slice:
            array := (^mem.Raw_Slice)(data.data);

            if array.data == nil {
                array.data = mem.alloc(len(v)*variant.elem_size, variant.elem.align, allocator);
                array.len  = len(v);
            } else if len(v) > array.len {
                fmt.println_err("Too many elements to fit slice");
                return false; // @error
            }

            for i in 0..<array.len {
                a := any{rawptr(uintptr(array.data) + uintptr(variant.elem_size * i)), variant.elem.id};
                if !unmarshal(a, v[i], allocator) do return false; // @error
            }

            return true;

        case runtime.Type_Info_Dynamic_Array:
            array := (^mem.Raw_Dynamic_Array)(data.data);

            if array.data == nil {
                array.data      = mem.alloc(len(v)*variant.elem_size, variant.elem.align, allocator);
                array.len       = len(v);
                array.cap       = len(v);
                array.allocator = allocator;
            } else if len(v) > array.cap {
                array.data = mem.resize(array.data, array.cap*variant.elem_size, len(v)*variant.elem_size, variant.elem.align, array.allocator);
                array.len  = len(v);
                array.cap  = len(v);
            } else if len(v) > array.len {
                array.len = len(v);
            }

            for i in 0..<array.len {
                a := any{rawptr(uintptr(array.data) + uintptr(variant.elem_size * i)), variant.elem.id};
                if !unmarshal(a, v[i], allocator) do return false; // @error
            }

            return true;
        }

    case string:
        switch variant in type_info.variant {
        case runtime.Type_Info_String:
            str := (^string)(data.data);

            if (str^) != "" {
                delete(str^);
            }

            str^ = strings.clone(v, allocator);

            return true;

        case runtime.Type_Info_Enum:
            for name, i in variant.names {
                if name == string(v) {
                    #complete switch val in &variant.values[i] {
                    case rune:    mem.copy(data.data, val, size_of(val^));
                    case i8:      mem.copy(data.data, val, size_of(val^));
                    case i16:     mem.copy(data.data, val, size_of(val^));
                    case i32:     mem.copy(data.data, val, size_of(val^));
                    case i64:     mem.copy(data.data, val, size_of(val^));
                    case int:     mem.copy(data.data, val, size_of(val^));
                    case u8:      mem.copy(data.data, val, size_of(val^));
                    case u16:     mem.copy(data.data, val, size_of(val^));
                    case u32:     mem.copy(data.data, val, size_of(val^));
                    case u64:     mem.copy(data.data, val, size_of(val^));
                    case uint:    mem.copy(data.data, val, size_of(val^));
                    case uintptr: mem.copy(data.data, val, size_of(val^));
                    }

                    return true;
                }
            }
        }

    case i64:
        switch variant in type_info.variant {
        case runtime.Type_Info_Integer:
            switch type_info.size {
            case 8:
                tmp := i64(v);
                mem.copy(data.data, &tmp, type_info.size);

            case 4:
                tmp := i32(v);
                mem.copy(data.data, &tmp, type_info.size);

            case 2:
                tmp := i16(v);
                mem.copy(data.data, &tmp, type_info.size);

            case 1:
                tmp := i8(v);
                mem.copy(data.data, &tmp, type_info.size);

            case: return false; // @error
            }

            return true;

        case runtime.Type_Info_Enum:
            return unmarshal(any{data.data, variant.base.id}, value);
        }

    case f64:
        if _, ok := type_info.variant.(runtime.Type_Info_Float); ok {
            switch type_info.size {
            case 8:
                tmp := f64(v);
                mem.copy(data.data, &tmp, type_info.size);

            case 4:
                tmp := f32(v);
                mem.copy(data.data, &tmp, type_info.size);

            case: return false; // @error
            }

            return true;
        }

    case bool:
        if _, ok := type_info.variant.(runtime.Type_Info_Boolean); ok {
            tmp := bool(v);
            mem.copy(data.data, &tmp, type_info.size);

            return true;
        }

    case: // @todo(bp): um, excuse me?
        mem.set(data.data, 0, type_info.size);
        return true;
    }

    return false;
}

unmarshal_value_to_type :: inline proc($T: typeid, value: Value, allocator := context.allocator) -> (T, bool) {
    tmp: T;
    ok := unmarshal(tmp, value, allocator);
    return tmp, ok;
}


unmarshal_string :: proc{unmarshal_string_to_any, unmarshal_string_to_type};

unmarshal_string_to_any :: inline proc(data: any, json: string, allocator := context.allocator) -> bool {
    if value, ok := parse_text(json); ok {
        defer destroy(value);

        return unmarshal(data, value, allocator);
    }

    return false;
}

unmarshal_string_to_type :: inline proc($T: typeid, json: string, allocator := context.allocator) -> (T, bool) {
    if value, ok := parse_text(json); ok {
        defer destroy(value);

        res: T;
        tmp := unmarshal(res, value, allocator);
        return res, tmp;
    }

    return ---, false;
}


unmarshal_file :: proc{unmarshal_file_to_any, unmarshal_file_to_type};

unmarshal_file_to_any :: inline proc(data: any, path: string, allocator := context.allocator) -> bool {
    if value, ok := parse_file(path); ok {
        defer destroy(value);

        return unmarshal(data, value, allocator);
    }

    return false;
}

unmarshal_file_to_type :: inline proc($T: typeid, path: string, allocator := context.allocator) -> (T, bool) {
    if value, ok := parse_file(path); ok {
        defer destroy(value);

        return unmarshal(T, value, allocator);
    }

    return ---, false;
}
