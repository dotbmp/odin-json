/*
 *  @Name:     json
 *  
 *  @Author:   Brendan Punsky
 *  @Email:    bpunsky@gmail.com
 *  @Creation: 28-11-2017 00:10:03 UTC-5
 *
 *  @Last By:   Brendan Punsky
 *  @Last Time: 05-12-2018 04:58:42 UTC-5
 *  
 *  @Description:
 *  
 */

package json

using import "core:runtime"

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"
import "core:unicode/utf16"

import pat "shared:path"



////////////////////////////
//
// GENERAL
////////////////////////////

error :: proc(format: string, args: ..any) {
    message := fmt.aprintf(format, ..args);
    defer delete(message);

    fmt.printf_err("Error: %s\n", message);
}

escape_string :: proc(str: string) -> string {
    buf: strings.Builder;

    for i := 0; i < len(str); {
        char, skip := utf8.decode_rune(cast([]u8) str[i:]);
        i += skip;

        switch char {
        case: 
            if utf8.valid_rune(char) {
                strings.write_rune(&buf, char);
            } else {
                error("Invalid rune in string: '%c' (%H)", char, char);
            }

        case '"':  fmt.sbprint(&buf, "\\\"");
        //case '\'': fmt.sbprint(&buf, "\\'");
        case '\\': fmt.sbprint(&buf, "\\\\");
        case '\a': fmt.sbprint(&buf, "\\a");
        case '\b': fmt.sbprint(&buf, "\\b");
        case '\f': fmt.sbprint(&buf, "\\f");
        case '\n': fmt.sbprint(&buf, "\\n");
        case '\r': fmt.sbprint(&buf, "\\r");
        case '\t': fmt.sbprint(&buf, "\\t");
        case '\v': fmt.sbprint(&buf, "\\v");
        }
    }

    return strings.to_string(buf);
}

unescape_string :: proc(str: string) -> string {
    buf: strings.Builder;

    for i := 0; i < len(str); {
        char, skip := utf8.decode_rune(([]u8)(str[i:]));
        i += skip;

        switch char {
        case: strings.write_rune(&buf, char);

        case '"': // @note: do nothing.

        case '\\':
            char, skip = utf8.decode_rune(([]u8)(str[i:]));
            i += skip;

            switch char {
            case '\\': strings.write_rune(&buf, '\\');
            case '\'': strings.write_rune(&buf, '\'');
            case '"':  strings.write_rune(&buf, '"');

            case 'a': strings.write_rune(&buf, '\a');
            case 'b': strings.write_rune(&buf, '\b');
            case 'f': strings.write_rune(&buf, '\f');
            case 'n': strings.write_rune(&buf, '\n');
            case 'r': strings.write_rune(&buf, '\r');
            case 't': strings.write_rune(&buf, '\t');
            case 'v': strings.write_rune(&buf, '\v');

            case 'u':
                lo, hi: rune;
                hex := [?]u8{'0', 'x', '0', '0', '0', '0'};

                c0, s0 := utf8.decode_rune(([]u8)(str[i:]));  hex[2] = (u8)(c0);  i += s0;
                c1, s1 := utf8.decode_rune(([]u8)(str[i:]));  hex[3] = (u8)(c1);  i += s1;
                c2, s2 := utf8.decode_rune(([]u8)(str[i:]));  hex[4] = (u8)(c2);  i += s2;
                c3, s3 := utf8.decode_rune(([]u8)(str[i:]));  hex[5] = (u8)(c3);  i += s3;

                lo = rune(strconv.parse_int(string(hex[:])));

                if utf16.is_surrogate(lo) {
                    c0, s0 := utf8.decode_rune(([]u8)(str[i:]));  i += s0;
                    c1, s1 := utf8.decode_rune(([]u8)(str[i:]));  i += s1;

                    if c0 == '\\' && c1 == 'u' {
                        c0, s0 = utf8.decode_rune(([]u8)(str[i:]));  hex[2] = (u8)(c0);  i += s0;
                        c1, s1 = utf8.decode_rune(([]u8)(str[i:]));  hex[3] = (u8)(c1);  i += s1;
                        c2, s2 = utf8.decode_rune(([]u8)(str[i:]));  hex[4] = (u8)(c2);  i += s2;
                        c3, s3 = utf8.decode_rune(([]u8)(str[i:]));  hex[5] = (u8)(c3);  i += s3;                      

                        hi = rune(strconv.parse_u64(string(hex[:])));
                        lo = utf16.decode_surrogate_pair(lo, hi);

                        if lo == utf16.REPLACEMENT_CHAR {
                            error("Invalid surrogate pair");
                        }
                    } else {
                        error("Expected a surrogate pair");
                    }
                }

                strings.write_rune(&buf, lo);

            case: error("Invalid escape character '%c'", char);
            }
        }
    }

    return strings.to_string(buf);
}



////////////////////////////
//
// TYPES
////////////////////////////

Spec :: enum {JSON, JSON5};

Null   :: distinct rawptr;
Int    ::          i64;
Float  ::          f64;
Bool   ::          bool;
String ::          string;
Array  :: distinct [dynamic]Value;
Object :: distinct map[string]Value;

Value :: struct {
    using token: Token,

    value: union {
        Null,
        Int,
        Float,
        Bool,
        String,
        Array,
        Object,
    },
}

Token :: struct {
    using cursor: Cursor,

    kind: Kind,
    text: string,
}

Kind :: enum {
    Invalid,

    Null,
    True,
    False,

    Symbol,
    
    Float,
    Integer,
    String,

    Colon,
    Comma,
    
    Open_Brace,
    Close_Brace,

    Open_Bracket,
    Close_Bracket,

    End,
}

Cursor :: struct {
    index: int,
    lines: int,
    chars: int,
}

destroy :: proc(value: Value) {
    switch v in value.value {
    case Object:
        for _, val in v do destroy(val);
        delete(cast(map[string]Value) v);

    case Array:
        for val in v do destroy(val);
        delete(cast([dynamic]Value) v);

    case String:
        delete(v);
    }
}



///////////////////////////
//
// LEXER
///////////////////////////

EOF :: utf8.RUNE_EOF;
EOB :: '\x00';

Lexer :: struct {
    using cursor: Cursor,
    path:   string,
    source: string,
    char:   rune,
    skip:   int,
    errors: int,
}

lex_error :: inline proc(using lexer : ^Lexer, format: string, args: ..any, loc := #caller_location) {
    message := fmt.aprintf(format, ..args);
    defer delete(message);

    fmt.printf_err("%s(%d,%d) Lexing error: %s\n", path, lines, chars, message);

    errors += 1;
}

next_char :: inline proc"contextless"(using lexer: ^Lexer) -> rune #no_bounds_check {
    index += skip;
    chars += 1;

    char, skip = inline utf8.decode_rune(([]u8)(source[index:]));

    return char;
}

lex :: proc(text: string, filename := "") -> []Token #no_bounds_check {
    using lexer := Lexer {
        cursor = Cursor{lines=1},
        path   = filename,
        source = text,
    };

    tokens := make([dynamic]Token, 0, 1024*1024*32); // @todo(bp): dial in
    toks := (^mem.Raw_Dynamic_Array)(&tokens);

    next_char(&lexer);

    loop: for {
        token := Token{cursor, Kind.Invalid, ---};

        switch char {
        case 'A'..'Z', 'a'..'z', '_':
            token.kind = Kind.Symbol;

            for {
                switch next_char(&lexer) {
                case 'A'..'Z', 'a'..'z', '0'..'9', '_': continue;
                }

                break;
            }

            switch source[token.index:index] {
            case "null":  token.kind = Kind.Null;
            case "true":  token.kind = Kind.True;
            case "false": token.kind = Kind.False;
            }

        case '+', '-':
            switch next_char(&lexer) {
            case '0'..'9': // continue
            case:          // @todo(bp): wut
            }
            fallthrough;

        case '0'..'9':
            token.kind = Kind.Integer;

            for {
                switch next_char(&lexer) {
                case '0'..'9': continue;
                case '.':
                    if token.kind == Kind.Float {
                        lex_error(&lexer, "Double radix in float");
                    } else {
                        token.kind = Kind.Float;
                    }
                    continue;
                }

                break;
            }

        case '"':
            token.kind = Kind.String;

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
            token.kind = Kind.Comma;
            next_char(&lexer);

        case ':':
            token.kind = Kind.Colon;
            next_char(&lexer);

        case '{':
            token.kind = Kind.Open_Brace;
            next_char(&lexer);

        case '}':
            token.kind = Kind.Close_Brace;
            next_char(&lexer);

        case '[':
            token.kind = Kind.Open_Bracket;
            next_char(&lexer);

        case ']':
            token.kind = Kind.Close_Bracket;
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

        case EOB, EOF, utf8.RUNE_ERROR: break loop; // @todo(bp): RUNE_ERROR seems sketchy

        case:
            lex_error(&lexer, "Illegal rune '%v' (%x)", char, (int)(char));
            next_char(&lexer);
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

    inline append(&tokens, Token{cursor, Kind.End, ""});

    return tokens[:];
}



///////////////////////////
//
// PARSING
///////////////////////////

Parser :: struct {
    spec: Spec,

    filename: string,
    source:   string,

    tokens: []Token,
    index:  int,

    errors: int,
}

parse_error :: proc(using parser: ^Parser, message: string, args: ..any, loc := #caller_location) {
    msg := fmt.aprintf(message, ..args);
    defer delete(msg);

    if index < len(tokens) {
        token := tokens[index];
        fmt.printf_err("%s(%d,%d) Error: %s\n", filename, token.lines, token.chars, msg);
    } else {
        fmt.printf_err("%s Error: %s\n", filename, msg);
    }

    errors += 1;
}

allow :: proc(using parser: ^Parser, kinds: ..Kind) -> ^Token #no_bounds_check {
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

expect :: proc(using parser: ^Parser, kinds: ..Kind, loc := #caller_location) -> ^Token {
    token := allow(parser, ..kinds);

    if token == nil {
        if index >= len(tokens) {
            parse_error(parser, "Cannot look past the end of the token stream");
        } else {
            parse_error(parser, "Expected %v; got %v", kinds, token.kind, loc);
        }
    }

    return token;
}

skip :: proc(using parser: ^Parser, kinds: ..Kind) {
    for token := allow(parser, ..kinds); token != nil; token = allow(parser, ..kinds) {
        // continue
    }
}

parse :: proc(using parser: ^Parser) -> (value: Value, success: bool) {
    success = true;

    if rhs := allow(parser, Kind.Open_Brace, Kind.Open_Bracket, Kind.Float, Kind.Integer, Kind.String, Kind.True, Kind.False, Kind.Null); rhs != nil {
        switch rhs.kind {
        case Kind.Open_Brace:
            object : Object;
            
            for {
                if lhs := allow(parser, Kind.String, Kind.Symbol); lhs != nil {
                    if expect(parser, Kind.Colon) == nil do success = false;
                    
                    if val, ok := parse(parser); ok {
                        text := unescape_string(lhs.text);
                        object[text] = val;
                    } else {
                        if expect(parser, Kind.Close_Brace) == nil do success = false;
                        break;
                    }
                } else {
                    if expect(parser, Kind.Close_Brace) == nil do success = false;
                    break;
                }

                if allow(parser, Kind.Comma) == nil {
                    if expect(parser, Kind.Close_Brace) == nil do success = false;
                    break;
                }
            }
            
            value.value = object;

        case Kind.Open_Bracket:
            array: Array;
            
            for {
                if val, ok := parse(parser); ok {
                    append(&array, val);
                } else {
                    if expect(parser, Kind.Close_Bracket) == nil do success = false;
                    break;
                }

                if allow(parser, Kind.Comma) == nil {
                    if expect(parser, Kind.Close_Bracket) == nil do success = false;
                    break;
                }
            }

            value.value = array;

        case Kind.String:  value.value = unescape_string(rhs.text);
        case Kind.Integer: value.value = strconv.parse_i64(rhs.text);
        case Kind.Float:   value.value = strconv.parse_f64(rhs.text);
        case Kind.True:    value.value = true;
        case Kind.False:   value.value = false;
        case Kind.Null:    value.value = Null{};

        case: success = false;
        }
    } else {
        success = false;
    }

    return;
}

parse_text :: inline proc(text: string, spec := Spec.JSON, path := "") -> (Value, bool) {
    parser := Parser{
        spec     = spec,
        filename = path,
        source   = text,
        tokens   = lex(text, path),
    };

    return parse(&parser);
}

parse_file :: inline proc(path: string, spec := Spec.JSON) -> (Value, bool) {
    if bytes, ok := os.read_entire_file(path); ok {
        return parse_text(string(bytes), spec, path);
    }

    return Value{}, false;
}



///////////////////////////
//
// PRINTING
///////////////////////////

buffer_print :: proc(buf: ^strings.Builder, value: Value, spec := Spec.JSON, indent := 0) {
    switch v in value.value {
    case Object:
        fmt.sbprint(buf, "{");

        if len(v) != 0 {
            fmt.sbprint(buf, "\n");
            indent += 1;

            i := 0;
            for key, value in v {
                for _ in 0..indent-1 do fmt.sbprint(buf, "    ");
     
                if spec == Spec.JSON do fmt.sbprint(buf, "\"");
                fmt.sbprint(buf, escape_string(key)); // @todo: check for whitespace in JSON5
                if spec == Spec.JSON do fmt.sbprint(buf, "\"");
     
                fmt.sbprint(buf, ": ");
     
                buffer_print(buf, value, spec, indent);

                if i != len(v)-1 || spec == Spec.JSON5 do fmt.sbprint(buf, ",");

                fmt.sbprintln(buf);

                i += 1;
            }

            indent -= 1;
            for _ in 0..indent-1 do fmt.sbprint(buf, "    ");
        }

        fmt.sbprint(buf, "}");

    case Array:
        fmt.sbprint(buf, "[");

        if len(v) != 0 {
            fmt.sbprint(buf, "\n");
            indent += 1;
            
            for value, i in v {
                for _ in 0..indent-1 do fmt.sbprint(buf, "    ");

                buffer_print(buf, value, spec, indent);

                if i != len(v)-1 || spec == Spec.JSON5 do fmt.sbprint(buf, ",");

                fmt.sbprintln(buf);
            }
            
            indent -= 1;
            for _ in 0..indent-1 do fmt.sbprint(buf, "    ");
        }

        fmt.sbprint(buf, "]");

    case String: fmt.sbprintf(buf, "\"%s\"", escape_string(v));
    case Bool:   fmt.sbprint(buf, v);
    case Float:  fmt.sbprint(buf, v);
    case Int:    fmt.sbprint(buf, v);
    case Null:   fmt.sbprint(buf, "null");
    case:        fmt.sbprint(buf, "!!!INVALID!!!");
    }
}

to_string :: inline proc(value: Value, spec := Spec.JSON) -> string {
    buf : strings.Builder;
    buffer_print(&buf, value, spec);
    return strings.to_string(buf);
}

print :: inline proc(value: Value, spec := Spec.JSON) {
    json := to_string(value, spec);
    defer delete(json);

    fmt.printf("\n%s\n\n", json);
}



///////////////////////////
//
// MARSHALLING
///////////////////////////

marshal :: proc(data: any, spec := Spec.JSON) -> (value : Value, success := true) {
    success = true;

    type_info := type_info_base(type_info_of(data.id));

    switch v in type_info.variant {
    case Type_Info_Integer:
        i: Int;

        switch type_info.size {
        case 8:  i = cast(Int) (cast(^i64)  data.data)^;
        case 4:  i = cast(Int) (cast(^i32)  data.data)^;
        case 2:  i = cast(Int) (cast(^i16)  data.data)^;
        case 1:  i = cast(Int) (cast(^i8)   data.data)^;
        }

        value.value = i;

    case Type_Info_Float:
        f: Float;

        switch type_info.size {
        case 8: f = cast(Float) (cast(^f64) data.data)^;
        case 4: f = cast(Float) (cast(^f32) data.data)^;
        }

        value.value = f;

    case Type_Info_String:
        str := (cast(^string) data.data)^;
        value.value = cast(String) str;

    case Type_Info_Boolean:
        b := cast(Bool) (cast(^bool) data.data)^;
        value.value = b;

    case Type_Info_Enum:
        for val, i in v.values {
            #complete switch vv in val {
            case rune:    value.value = strings.clone(v.names[vv]);
            case i8:      value.value = strings.clone(v.names[vv]);
            case i16:     value.value = strings.clone(v.names[vv]);
            case i32:     value.value = strings.clone(v.names[vv]);
            case i64:     value.value = strings.clone(v.names[vv]);
            case int:     value.value = strings.clone(v.names[vv]);
            case u8:      value.value = strings.clone(v.names[vv]);
            case u16:     value.value = strings.clone(v.names[vv]);
            case u32:     value.value = strings.clone(v.names[vv]);
            case u64:     value.value = strings.clone(v.names[vv]);
            case uint:    value.value = strings.clone(v.names[vv]);
            case uintptr: value.value = strings.clone(v.names[vv]);
            }
        }

    case Type_Info_Array:
        array := make([dynamic]Value, 0, v.count);

        for i in 0..v.count-1 {
            if tmp, ok := marshal(any{rawptr(uintptr(data.data) + uintptr(v.elem_size*i)), v.elem.id}, spec); ok {
                append(&array, tmp);
            } else {
                success = false;
                return;
            }
        }

        value.value = cast(Array) array;

    case Type_Info_Slice:
        a := cast(^mem.Raw_Slice) data.data;

        array := make([dynamic]Value, 0, a.len);

        for i in 0..a.len-1 {
            if tmp, ok := marshal(any{rawptr(uintptr(a.data) + uintptr(v.elem_size*i)), v.elem.id}, spec); ok {
                append(&array, tmp);
            } else {
                success = false;
                return;
            }
        }

        value.value = cast(Array) array;

    case Type_Info_Dynamic_Array:
        array := make([dynamic]Value);

        a := cast(^mem.Raw_Dynamic_Array) data.data;

        for i in 0..a.len-1 {
            if tmp, ok := marshal(transmute(any) any{rawptr(uintptr(a.data) + uintptr(v.elem_size*i)), v.elem.id}, spec); ok {
                append(&array, tmp);
            } else {
                success = false;
                return;
            }
        }

        value.value = cast(Array) array;

    case Type_Info_Struct:
        object: map[string]Value;

        for ti, i in v.types {
            if tmp, ok := marshal(any{rawptr(uintptr(data.data) + uintptr(v.offsets[i])), ti.id}, spec); ok {
                object[v.names[i]] = tmp;
            } else {
                success = false;
                return;
            }
        }

        value.value = cast(Object) object;

    case Type_Info_Map:
        // @todo: implement. ask bill about this, maps are fucky
        success = false;

    case:
        success = false;
    }

    return;
}

marshal_string :: inline proc(data: any, spec := Spec.JSON) -> (string, bool) {
    if value, ok := marshal(data, spec); ok {
        return to_string(value, spec), true;
    }

    return "", false;
}

marshal_file :: inline proc(path: string, data: any, spec := Spec.JSON) -> bool {
    if str, ok := marshal_string(data, spec); ok {
        return os.write_entire_file(path, cast([]u8) str);
    }

    return false;
}



///////////////////////////
//
// UNMARSHALLING
///////////////////////////

unmarshal :: proc{unmarshal_value_to_any, unmarshal_value_to_type};

unmarshal_value_to_any :: proc(data: any, value: Value, spec := Spec.JSON) -> bool {
    type_info := type_info_base(type_info_of(data.id));
    type_info  = type_info_base(type_info); // @todo: dirty fucking hack, won't hold up

    switch v in value.value {
    case Object:
        switch variant in type_info.variant {
        case Type_Info_Struct:
            for field, i in variant.names {
                // @todo: stricter type checking and by-order instead of by-name as an option
                a := any{rawptr(uintptr(data.data) + uintptr(variant.offsets[i])), variant.types[i].id};
                if !unmarshal(a, v[field], spec) do return false; // @error
            }

            return true; 
        
        case Type_Info_Map:
            // @todo: implement. ask bill about this, maps are a daunting prospect because they're fairly opaque
        }

        return false; // @error

    case Array:
        switch variant in type_info.variant {
        case Type_Info_Array:
            if len(v) > variant.count do return false; // @error

            for i in 0..variant.count-1 {
                a := any{rawptr(uintptr(data.data) + uintptr(variant.elem_size * i)), variant.elem.id};
                if !unmarshal(a, v[i], spec) do return false; // @error
            }

            return true;

        case Type_Info_Slice:
            array := (^mem.Raw_Slice)(data.data);

            if len(v) > array.len do return false; // @error
            array.len = len(v);

            for i in 0..array.len {
                a := any{rawptr(uintptr(array.data) + uintptr(variant.elem_size * i)), variant.elem.id};
                if !unmarshal(a, v[i], spec) do return false; // @error
            }

            return true;

        case Type_Info_Dynamic_Array:
            array := (^mem.Raw_Dynamic_Array)(data.data);

            if array.cap == 0 {
                array.data      = mem.alloc(len(v)*variant.elem_size);
                array.cap       = len(v);
                array.allocator = context.allocator;
            }

            if len(v) > array.cap {
                context = mem.context_from_allocator(array.allocator);
                mem.resize(array.data, array.cap, len(v)*variant.elem_size);
            }

            array.len = len(v);

            for i in 0..array.len-1 {
                a := any{rawptr(uintptr(array.data) + uintptr(variant.elem_size * i)), variant.elem.id};
                if !unmarshal(a, v[i], spec) do return false; // @error
            }

            return true;

        case: return false; // @error
        }

    case String:
        switch variant in type_info.variant {
        case Type_Info_String:
            tmp := string(v);
            mem.copy(data.data, &tmp, size_of(string));

            return true;

        case Type_Info_Enum:
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

        return false; // @error

    case Int:
        switch variant in type_info.variant {
        case Type_Info_Integer:
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

        case Type_Info_Enum:
            return unmarshal(any{data.data, variant.base.id}, value, spec);
        }

        return false; // @error

    case Float:
        if _, ok := type_info.variant.(Type_Info_Float); ok {
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

        return false; // @error

    case Bool:
        if _, ok := type_info.variant.(Type_Info_Boolean); ok {
            tmp := bool(v);
            mem.copy(data.data, &tmp, type_info.size);

            return true;
        }

        return false; // @error

    case Null:
        mem.set(data.data, 0, type_info.size);
        return true;
    
    case: return false; // @error
    }

    panic("Unreachable code.");
    return false;
}

unmarshal_value_to_type :: inline proc($T: typeid, value: Value, spec := Spec.JSON) -> (T, bool) {
    tmp: T;
    ok := unmarshal(tmp, value, spec);
    return tmp, ok;
}


unmarshal_string :: proc{unmarshal_string_to_any, unmarshal_string_to_type};

unmarshal_string_to_any :: inline proc(data: any, json: string, spec := Spec.JSON) -> bool {
    if value, ok := parse_text(json, spec); ok {
        return unmarshal(data, value, spec);
    }

    return false;
}

unmarshal_string_to_type :: inline proc($T: typeid, json: string, spec := Spec.JSON) -> (T, bool) {
    if value, ok := parse_text(json, spec); ok {
        res : T;
        tmp := unmarshal(res, value, spec);
        return res, tmp;
    }

    return T{}, false;
}


unmarshal_file :: proc{unmarshal_file_to_any, unmarshal_file_to_type};

unmarshal_file_to_any :: inline proc(data: any, path: string, spec := Spec.JSON) -> bool {
    if value, ok := parse_file(path, spec); ok {
        return unmarshal(data, value, spec);
    }

    return false;
}

unmarshal_file_to_type :: inline proc($T: typeid, pat: string, spec := Spec.JSON) -> (T, bool) {
    if value, ok := parse_file(path, spec); ok {
        return unmarshal(T, value, spec);
    }

    return T{}, false;
}
