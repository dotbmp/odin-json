A JSON parser for the Odin language.

It features parse-to-tree as well as marshalling and unmarshalling to and from structs.

Feel free to do whatever with this software.

There is one dependency, [`odin-path`](https://github.com/bpunsky/odin-path), which is used for a bit of file system stuff, though I do plan on removing that eventually so `odin-json` will be usable on its own. Just remember to keep all your odin libraries in your `shared:` collection for now (`/path/to/odin/shared` by default). 

`json_test.odin` is a super-shoddy little test suite, and the accompanying JSON files are for that. `tempo.odin` is temporarily needed for doing timings - I do want a fast lexer and parser.

TODO:
- Add full JSON5 support and allow the user to choose strict JSON
- Remove dependency on `odin-path`
- Remove `tempo.odin`
- Clean up the test file
