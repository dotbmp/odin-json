import win32 "core:sys/windows.odin";
import "core:fmt.odin";
import "core:hash.odin";
import "core:mem.odin";
import "core:os.odin";
import "core:raw.odin";
import "core:strconv.odin";

when ODIN_OS == "windows" {
    foreign_system_library "kernel32.lib";
}


padding :: proc(ptr: rawptr, align: int) -> int #inline {
    x := cast(int) ((cast(uint) ptr) % (cast(uint) align));

    return x > 0 ? align-x : 0;
}

// Console Utils

    foreign kernel32 {
        read_console :: proc(h: win32.Handle, buf: rawptr, to_read: u32, bytes_read: ^u32, input_control: rawptr) -> win32.Bool #cc_std #link_name "ReadConsoleA" ---;
    }

    read_line :: proc(chunk: u32 = 16) -> string {
        buf := cast(^u8)alloc(int(chunk));

        read, total: u32;

        for read_console(win32.Handle(os.stdin), buf + total, chunk, &read, nil) == win32.TRUE && read > 0 {
            total += read;

            if read == chunk { 
                if (buf + (total - 2))^ == '\r' && (buf + (total - 1))^ == '\n' do break;

                buf = cast(^u8)resize(buf, int(total), int(total + chunk));
            } else {
                break;
            }
        }

        raw_line := raw.String {
            data = buf,
            len  = int(total - 2),
        };

        return transmute(string) raw_line;
    }

    wait_for_enter :: proc() #inline {
        // TODO: trigger on any key press, don't break line
        read: u32;
        buf:  u32;
        read_console(win32.Handle(os.stdin), &buf, size_of(buf), &read, nil);
    }

    read_args :: proc() -> []string {
        input := read_line();
        defer free(input);

        list:   [dynamic]string;
        buffer: [dynamic]u8;

        buf := cast(^raw.Dynamic_Array)&buffer;
        ls  := cast(^raw.Dynamic_Array)&list;

        quoted := false;

        for char in input {
            if !quoted && char == ' ' || char == '\t' {
                if buf.len > 0 {
                    append(&list, transmute(string) raw.String{cast(^u8)buf.data, buf.len});
                    buffer = make([dynamic]u8);
                }
            } else {
                append(&buffer, u8(char));
            }

            if char == '"' do quoted = !quoted;
        }
        
        if buf.len > 0 do append(&list, transmute(string) raw.String{cast(^u8)buf.data, buf.len});

        for str in list {
            if len(str) > 0 && str[0] != '"' {
                to_lower(str);
            }
        }

        return transmute([]string) raw.Slice{ls.data, ls.len, ls.cap};
    }

    free_args :: proc(args: ^[]string) #inline {
        if len(args) > 0 {
            for arg in args do free(arg);
            free(args^);
            args^ = []string{};
        }
    }

// Remove Procs

    // remove requires indices to be in order or it can fuck up big time
    remove :: proc(slice: ^[]$T, indices: ...int) {
        assert(slice != nil && len(slice^) != 0);

        a := cast(^raw.Slice) slice;

        for i := len(indices) - 1; i >= 0; i -= 1 {
            index := indices[i];

            if index < 0 || a.len <= 0 || a.len <= index do return;

            if index < a.len - 1 {
                slice[index] = slice[a.len-1];
            }

            a.len -= 1;
        }
    }

    remove :: proc(array: ^[dynamic]$T, indices: ...int) #inline do
        remove(cast(^[]T) array, ...indices);

    remove_ordered :: proc(slice: ^[]$T, indices: ...int) {
        assert(slice != nil && len(slice^) != 0);

        a := cast(^raw.Dynamic_Array) slice;

        for idx, i in indices {
            index := idx - i;

            if index < 0 || a.len <= 0 || a.len <= index do return;

            if index < a.len - 1 do
                mem.copy(&slice[index], &slice[index+1], size_of(T) * (a.len - index));
            
            a.len -= 1;
        }
    }

    remove_ordered :: proc(array: ^[dynamic]$T, indices: ...int) #inline do
        remove_ordered(cast(^[]T) array, ...indices);

    remove_value :: proc(slice: ^[]$T, values: ...T) {
        assert(slice != nil && len(slice^) != 0);

        indices := make([]int, 0, len(values));
        defer free(indices);

        for i in 0..len(slice) {
            for value in values {
                when T == any {
                    if slice[i].data == value.data do append(&indices, i);
                } else {
                    if slice[i] == value do append(&indices, i);
                }
            }
        }

        remove(slice, ...indices);
    }

    remove_value :: proc(array: ^[dynamic]$T, values: ...T) #inline do
        remove_value(cast(^[]T) array, values);

    remove_value_ordered :: proc(slice: ^[]$T, values: ...T) {
        assert(slice != nil && len(slice^) != 0);

        indices := make([]int, 0, len(values));
        defer free(indices);

        for i in 0..len(slice) {
            for value in values {
                when T == any {
                    if slice[i].data == value.data do append(&indices, i);
                } else {
                    if slice[i] == value do append(&indices, i);
                }
            }
        }

        remove_ordered(slice, ...indices);
    }

    remove_value_ordered :: proc(array: ^[dynamic]$T, values: ...T) #inline do
        remove_value_ordered(cast(^[]T) array, ...values);

    pop_front :: proc(array: ^[dynamic]$T) -> T #inline {
        tmp := array[0];
        remove(array, 0);
        return tmp;
    }

// Type Stuff

    type_name_of :: proc(T: type)          -> string #inline do return type_name_of(type_info_of(T));
    type_name_of :: proc(x: any)           -> string #inline do return type_name_of(x.type_info);
    type_name_of :: proc(info: ^Type_Info) -> string #inline do return fmt.aprint(info);

    type_hash_of :: proc(info: ^Type_Info) -> u64 #inline do return hash.fnv64(transmute([]u8) mem.slice_ptr(info, size_of(Type_Info)));
    type_hash_of :: proc(T: type)          -> u64 #inline do return type_hash_of(type_info_of(T));
    type_hash_of :: proc(x: any)           -> u64 #inline do return type_hash_of(x.type_info);
    
    new :: proc(info: ^Type_Info) -> any do return transmute(any) raw.Any{alloc(info.size, info.align), info};

// any Procs

    new_any :: proc(a: any) -> any {
        tmp := a.data;

        a.data = alloc(a.type_info.size, a.type_info.align);

        mem.copy(a.data, tmp, a.type_info.size);

        return a;
    }

// String Procs

    c_string_const :: proc(str: string) -> ^u8 #inline {
        assert(str[len(str)-1] == '\x00');
        return &str[0]; 
    }

    c_string :: proc(str: string) -> ^u8 #inline {
        c := cast(^u8) alloc(len(str)+1);
        mem.copy(c, &str[0], len(str));
        (c + len(str))^ = '\x00';
        return c;
    }

    from_c_string :: proc(cstr: ^u8) -> string {
        if cstr == nil do return "";
        len := 0;
        for (cstr + len)^ != 0 do len += 1;
        return transmute(string) raw.String{cstr, len};
    }

    clone_string :: proc(str: string) -> string {
        buf := make([]u8, len(str), len(str));

        copy(buf, cast([]u8) str);

        return cast(string) buf;
    }

    find_last_index :: proc(str, seq: string) -> int #cc_contextless {
        index := -1;

        for char, i in str {
            found := true;

            for char2 in seq do if char != char2 do found = false;

            if found do index = i;
        }

        return index;
    }

    is_upper :: proc(char: rune) -> bool #inline {
        return char >= 'A' && char <= 'Z';
    }

    is_upper :: proc(char: u8) -> bool #inline do return is_upper(cast(rune)char);

    is_lower :: proc(char: rune) -> bool #inline {
        return char >= 'a' && char <= 'z';
    }

    is_lower :: proc(char: u8) -> bool #inline do return is_lower(cast(rune)char);

    is_letter :: proc(char: rune) -> bool #inline {
        return is_upper(char) || is_lower(char);
    }

    is_letter :: proc(char: u8) -> bool #inline do return is_letter(cast(rune)char);

    is_digit :: proc(char: rune) -> bool #inline {
        return char >= '0' && char <= '9';
    }

    is_digit :: proc(char: u8) -> bool #inline do return is_digit(cast(rune)char);

    to_lower :: proc(char: rune) -> rune #inline {
        if is_upper(char) {
            return char - ('A' - 'a');
        }

        return char; 
    }

    to_lower :: proc(char: u8) -> u8 #inline {
        return cast(u8)to_lower(cast(rune)char);
    }

    to_upper :: proc(char: rune) -> rune #inline {
        if is_lower(char) {
            return char + ('A' - 'a');
        }

        return char;
    }

    to_upper :: proc(char: u8) -> u8 #inline {
        return cast(u8)to_upper(cast(rune)char);
    }

    is_number :: proc(str: string) -> bool {
        for char in str {
            if !is_digit(char) && char != '-' && char != '+' && char != '.' {
                return false;
            }
        }

        return true;
    }

    to_lower :: proc(str: string) -> string {
        for i in 0..len(str) {
            str[i] = to_lower(str[i]);
        }

        return str;
    }

    to_upper :: proc(str: string) -> string {
        for i in 0..len(str) {
            str[i] = to_upper(str[i]);
        }

        return str;
    }

    to_title :: proc(str: string) -> string {
        last: u8;

        for i in 0..len(str) {
            char := str[i];

            if is_letter(char) {
                if is_letter(last) || is_digit(last) || last == '\'' {
                    str[i] = to_lower(char);
                } else {
                    str[i] = to_upper(char);
                }
            }

            last = char;
        }

        return str;
    }

    copy_lower :: proc(str: string) -> string #inline {
        tmp := make([]u8, len(str));
        copy(tmp, cast([]u8)str);
        to_lower(cast(string)tmp);
        return cast(string)tmp;
    }

    copy_upper :: proc(str: string) -> string #inline {
        tmp := make([]u8, len(str));
        copy(tmp, cast([]u8)str);
        to_upper(cast(string)tmp);
        return cast(string)tmp;
    }

    copy_title :: proc(str: string) -> string #inline {
        tmp := make([]u8, len(str));
        copy(tmp, cast([]u8)str);
        to_title(cast(string)tmp);
        return cast(string)tmp;
    }

    trim :: proc(str, set: string) -> string {
        start, end: int;

        for i := 0; i < len(str); i -= 1 {
            for char in cast([]u8) set do if str[i] == char do start = i + 1;
        }

        for i := len(str)-1; i < len(str); i -= 1 {
            for char in cast([]u8) set do if str[i] == char do end = i;
        }

        if start < end do return clone_string(cast(string) str[start..end]); else do return "";
    }

    is_quoted :: proc(str: string) -> bool {
        return len(str) > 1 ? str[0] == '"' && str[len(str)-1] == '"' : false;
    }

    unquote :: proc(str: string) -> string {
        if is_quoted(str) {
            return clone_string(cast(string) str[1..len(str)-1]);
        } else do return str;
    }

    to_string :: proc(char: rune) -> string #inline {
        return transmute(string) raw.String {
            data = cast(^u8) &char,
            len  = size_of(char),
        };
    }

    compare_strings_lower :: proc(lhs, rhs: string) -> bool {
        if len(lhs) != len(rhs) do
            return false;
        
        if (lhs == "" || rhs == "") &&
           (lhs != "" || rhs != "") do
            return false;

        for i in 0..len(lhs) {
            if to_lower(lhs[i]) != to_lower(rhs[i]) do
                return false;
        }

        return true;
    }

    escape_string :: proc(str: string) -> string {
        buf: [dynamic]u8;

        escape := false;

        for char in str {
            if escape {
                c: rune;

                match char {
                // @todo: support escaped newline
                case 'n': c = '\n';
                case 'r': c = '\r';
                case 't': c = '\t';
                case:     c = char; 
                }

                append(&buf, to_string(c));
                escape = false;
            } else {
                match char {
                // @todo: err if quotes not on ends of string
                case '\\': escape = true;
                case '"':  continue;
                case:      append(&buf, to_string(char));
                }
            }
        }

        return to_string(buf);
    }

    unescape_string :: proc(str: string) -> string {
        buf: [dynamic]u8;

        append(&buf, '"');

        for char in str {
            match char {
            case '\r': append(&buf, '\\'); append(&buf, to_string('r'));
            case '\n': append(&buf, '\\'); append(&buf, to_string('n'));
            case '\t': append(&buf, '\\'); append(&buf, to_string('t'));
            case '"':  append(&buf, '\\'); append(&buf, to_string(char));
            case '\'': append(&buf, '\\'); append(&buf, to_string(char));
            case:      append(&buf, to_string(char));
            }
        }

        append(&buf, to_string('"'));

        return to_string(buf);
    }

// Container Transformations

    // @note: copy the data?
    to_dynamic :: proc(slc: []$T) -> [dynamic]T #inline {
        dyn := raw.Dynamic_Array {
            cap       = cap(slc),
            allocator = context.allocator,
        };

        (cast(^[]T) &dyn)^ = slc;

        return transmute([dynamic]T) dyn;
    }

    // @note: this is only a good idea if the string is allocated, and by the context allocator!!!
    // maybe not even then!
    to_dynamic :: proc(str: string) -> [dynamic]u8 #inline {
        dyn := raw.Dynamic_Array {
            cap       = len(str),
            allocator = context.allocator,
        };

        (cast(^string) &dyn)^ = str;

        return transmute([dynamic]u8) dyn;
    }

    to_slice :: proc(dyn: [dynamic]$T) -> []T #inline do return (cast(^[]T) &dyn)^;

    to_slice :: proc(str: string) -> []u8 #inline {
        slc := raw.Slice {
            cap = len(str),
        };

        (cast(^string) &slc)^ = str;

        return transmute([]u8) slc;
    }

    to_string :: proc(dyn: [dynamic]u8) -> string #inline do return (cast(^string) &dyn)^;
    to_string :: proc(slc: []u8)        -> string #inline do return (cast(^string) &slc)^;

