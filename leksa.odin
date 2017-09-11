import "core:os.odin";
import "core:utf8.odin";

// @todo: support streaming files

File_Info :: struct {
    path: string;
    rel:  string;
    dir:  string; // 
    name: string; // not allocated
    ext:  string; //
}

Cursor :: struct {
    runes: int; // rune index
    bytes: int; // byte index
    lines: int; // line number
    chars: int; // char number
}

make_cursor :: proc() -> Cursor #inline do
    return Cursor{0, 0, 1, 1};

Lexer :: struct {
    from_file:    bool;
    file:         File_Info;
    source:       string;
    using cursor: Cursor;
}

Lexeme :: struct {
    using cursor: Cursor;
    text:         string;
}

make_lexer :: proc(source: string) -> Lexer #inline do
    return Lexer{source=source, cursor=make_cursor()};

load_lexer :: proc(path: string) -> (Lexer, bool) #inline {
    if bytes, ok := os.read_entire_file(path); ok do
        return Lexer {
            from_file=true,
            // file     =make_file_info(path), @todo: implement `make_file_info`
            source   =cast(string) bytes,
            cursor   =make_cursor(),
        }, true;
    return Lexer{}, false;
}

swap_cursor :: proc(lexer: ^Lexer, cursor: Cursor) -> Cursor #inline {
    tmp := lexer.cursor;
    lexer.cursor = cursor;
    return tmp;
}

line_break :: proc(using lexer: ^Lexer) #inline {
    lines += 1;
    chars  = 0;    
}

peek :: proc(using lexer: ^Lexer) -> rune #inline {
    if bytes < len(source) {
        char, length := utf8.decode_rune(source[bytes..]);
        return length > 0 ? char : 0;
    } else do return 0;
}

next :: proc(using lexer: ^Lexer) -> rune #inline {
    if bytes < len(source) {
        _, skip := utf8.decode_rune(source[bytes..]);

        bytes += skip;
        runes += 1;
        chars += 1;

        char, length := utf8.decode_rune(source[bytes..]);

        return length > 0 ? char : 0;
    } else do return 0;
}

// returns < 0: error
// returns   0: soft failure
// returns > 0: token type
Read_Proc :: #type proc(lexer: ^Lexer) -> int; 

read :: proc(lexer: ^Lexer, reader: Read_Proc) -> (Lexeme, int) {
    start := swap_cursor(lexer, lexer.cursor);

    if code := reader(lexer); code <= 0 {
        swap_cursor(lexer, start);
        return Lexeme{}, code;
    } else {
        return Lexeme{start, cast(string) lexer.source[start.bytes..lexer.bytes]}, code;
    }
}

