import "core:fmt.odin";

import "json.odin";

// corresponds to /test.json
// shows off marshalling into an arbitrary pointer
Test :: struct {
    Kind :: enum int {
        Hello, World,
    };

    message: string;
    number:  ^int;
    stuff:   [4]int;
    vec3:    [vector 3]f32;
    bools:   [6]bool;
};

// corresponds to /test2.json
// shows off an invalid enum value
Test2 :: struct #ordered {
    Country :: enum i16 {
        United_States,
        New_Zealand,
        North_Korea,
        Moon_Colony,
        Vatican_City,
    };

    Person :: struct #ordered {
        first_name:  string;
        last_name:   string;

        nickname:    string;

        age:         int;

        nationality: Country;
    };

    number: int;
    people: [5]Person;

    pointlessness_factor: f32;
};

main :: proc() {
    TYPE     :: Test;
    filename := "test.json";

    fmt.printf("parsing %s...\r\n", filename);

    if test, ok := json.parse_file(TYPE, filename); ok {
        fmt.println("test =", test);
        
        when TYPE == Test do
            fmt.println("test.number^ =", test.number^);
    }
    else do fmt.println("json parsing failed.");
}
