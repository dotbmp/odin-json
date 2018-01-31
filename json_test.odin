/*
 *  @Name:     json_test
 *  
 *  @Author:   Brendan Punsky
 *  @Email:    bpunsky@gmail.com
 *  @Creation: 31-01-2018 00:26:30 UTC-5
 *
 *  @Last By:   Brendan Punsky
 *  @Last Time: 31-01-2018 05:30:55 UTC-5
 *  
 *  @Description:
 *  
 */

import "core:fmt.odin"
import "core:os.odin"

import "tempo.odin"

using import _ "json.odin"



////////////////////////////////
//
// TEST CASES
////////////////////////////////

/*
test1 :: proc() {
    val : Value;
    defer destroy(val);
    
    root : Object;

    root["ival"] = 123;
    root["sval"] = cast(String) clone("Hello, World!");
    root["bval"] = true;
    root["aval"] = cast(Array) clone([]Value{321, cast(String) clone("foo"), false, Null{}});

    json := to_string(root);
    defer free(json);

    fmt.printf("\n%s\n\n", json);

    obj := parse(json);

    print(obj, Spec.JSON5);
}
*/

test2 :: proc() {
    json := `
{
    "glossary": {
        "title": "example glossary",
        "GlossDiv": {
            "title": "S",
            "GlossList": {
                "GlossEntry": {
                    "ID": "SGML",
                    "SortAs": "SGML",
                    "GlossTerm": "Standard Generalized Markup Language",
                    "Acronym": "SGML",
                    "Abbrev": "ISO 8879:1986",
                    "GlossDef": {
                        "para": "A meta-markup language, used to create markup languages such as DocBook.",
                        "GlossSeeAlso": ["GML", "XML"]
                    },
                    "GlossSee": "markup"
                }
            }
        }
    }
}
    `;

    if obj, ok := parse_string(json); ok {
        print(obj);
    } else {
        fmt.println("failed!");
    }
}

test3 :: proc() {
    Test_Message :: struct {
        foo: string,
        bar: int,
        bools: [4]bool,
    };

    json := `
{
    "bools": [false, true, true, false],
    "foo": "Hello, World!",
    "bar": 123
}
    `;

    message: Test_Message;

    obj, _ := parse_string(json);
    print(obj, Spec.JSON5);

    unmarshal_string(message, json);

    fmt.println(message);

    fmt.println();
}

Message :: struct {
    category:    string,
    air_date:    string,
    question:    string,
    value:       string,
    answer:      string,
    round:       string,
    show_number: string,
}

test4 :: proc() {
    fmt.println("started...");
    timer := tempo.make_timer();
    
    if obj, ok := parse_file("jeopardy.json"); ok {
        fmt.printf("done... (%f sec)\n\n", tempo.seconds(tempo.query(&timer)));
        
        messages := make([dynamic]Message, 0, 300_000);

        if unmarshal(messages, obj) {
            for msg in messages do fmt.println(msg.answer);
            fmt.println();
            fmt.printf("%d messages\n", len(messages));
        } else {
            fmt.println("Unmarshalling failed.");
        }
    } else {
        fmt.println("Parsing failed.");
    }
}

tree_print :: proc(value : Value, indent := 0) {
    for in 0..indent do fmt.print("    ");
    switch v in value.value {
    case Null:   fmt.println("null");
    case Bool:   fmt.println(v);
    case Int:    fmt.println(v);
    case Float:  fmt.println(v);
    case String: fmt.println(v);

    case Array:
        for elem, i in v {
            if i != 0 do for in 0..indent do fmt.print("    ");
            fmt.println("array");
            tree_print(elem, indent+1);
        }

    case Object:
        i := 0;
        for key, elem in v {
            if i != 0 do for in 0..indent do fmt.print("    ");
            fmt.println(key);
            tree_print(elem, indent+1);
            i += 1;
        }

    case: fmt.println("[!! INVALID !!]", value.value);
    }
}

test5 :: proc() {
    fmt.println("started...");
    timer := tempo.make_timer();

    if root, ok := parse_file("twitch.json"); ok {
        fmt.printf("done... (%f sec)\n\n", tempo.seconds(tempo.query(&timer)));
        tree_print(root);
    } else {
        fmt.println("Parsing failed.");
    }
}

view :: proc(json: string, from, to: int) -> string {
    return cast(string) json[max(0, from)...min(to, len(json)-1)];
}

test6 :: proc() {
    Foo :: struct {
        test: string,
    }

    text := `{"test": "\u00E9\u00E9\u00E9\uD83D\uDE02\u00E9"}`;

    if foo, ok := unmarshal_string(Foo, text); ok {
        fmt.println(foo.test);
    } else {
        fmt.println("failed!");
    }
}

test7 :: proc() {
    if val, ok := parse_file("test.json"); ok {
        tree_print(val);
    } else {
        fmt.println("failed!");
    }
}

profile_lexer :: proc() {
    FILE :: "jeopardy.json";

    if bytes, ok := os.read_entire_file(FILE); ok {
        timer := tempo.make_timer();
        
        tokens := lex(string(bytes));

        time := tempo.query(&timer);

        fmt.printf("%d tokens in %fms, %f ms/token, %f tokens/ms\n",
            len(tokens),
            tempo.ms(time),
            tempo.ms(time)/f64(len(tokens)),
            f64(len(tokens))/tempo.ms(time),
        );
    }
}

main :: proc() {
    profile_lexer();
}
