# cosock

![cosock logo](./cosock%20logo.svg)

cosock is a library that provides a coroutine executor for luasocket code.
Unlike existing coroutine executors it aims to provide a socket facade API
inside each coroutine that is as close to the native luasocket API as is
possible.

Note: currenly the only goals are to provide the API as documented,
undocumented APIs are out of scope for now (however, small quirks that
are heavily depened on in the ecosystem will be considered).

For now see the tests folder for example usage.

## Testing

To run all tests run:

    luarocks test

The first time you run the tests, you may want to run this to install the test
dependencies locally:

    luarocks test --local

Individual tests can be run from the repo root directly:

    lua test/asyncify/asyncify-works.lua
