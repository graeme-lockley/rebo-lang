There is so much to do.  The following is my work list on this project.  I will continuously juggle the sequence of these tasks as I work on them depending on what I would like to get working next.

# Language Features

## Literals:

- [X] Unit literal
- [X] Boolean literal
- [X] Integer literal
- [X] Char literal
- [X] Float literal

## Values

- [X] Let declaration
- [X] Assignment without destructing
- [ ] Assignment with destructing

## Functions

- [X] Add function literal
- [X] Add function call
- [X] Add function value
- [X] Add support for `...` argument to get the remainder of the arguments as a sequence

## Sequences

- [X] Add support for a literal sequence
- [X] Add support for `...` when incorporating a literal sequence
- [X] Add support for `[]` to access an element in a sequence based on value
- [X] Add support for `[start:end]` to access a slice of sequence
- [X] Add support for `[] = value` to update a sequence
- [X] Add support for `[start:end] = value` to update a slice of sequence
- [ ] Add support for `[start:end] = ()` to remove a slice from a sequence
- [X] `+` concatenates two sequences
- [ ] Add support destructuring a sequence into variables
- [X] Move all the functions into the SequenceKind rather than having them lying all over the code base and forcing knowledge of the implementation

## Strings

- [X] Literal string without interpolation
- [ ] Literal string interpolation
- [X] `[]` to access a char in a string
- [X] `[start:end]` to access a slice of a string
- [X] `+` concatenates two strings
- [ ] Move all the functions into the StringKind rather than having them lying all over the code base and forcing knowledge of the implementation

## Records

- [X] Add support for a literal record
- [ ] Add support for a literal string as a literal record field name
- [X] Add support for `...` when incorporating a literal record
- [X] Add support for `.field` to access a record's field
- [X] Add support for `[]` to access a field in a record based on value
- [X] Add support for `.field = value` to update a record
- [X] Add support for `[] = value` to update a record's field
- [ ] `+` concatenates two records
- [ ] Add support for destructing a record into variables
- [ ] Move all the functions into the RecordKind rather than having them lying all over the code base and forcing knowledge of the implementation

## Scope

- [ ] Move all the functions into the ScopeKind rather than having them lying all over the code base and forcing knowledge of the implementation

# Operators

- [X] Integer '+'
- [X] Integer '-'
- [X] Integer '*'
- [X] Integer '/'
- [X] Integer '%'
- [X] Float '+'
- [X] Float '-'
- [X] Float '*'
- [X] Float '/'
- [X] Integer '=='
- [X] Integer '!='
- [X] All '=='
- [X] All '!='
- [X] All '<'
- [X] All '<='
- [X] All '>'
- [X] All '>='
- [X] Boolean '&&'
- [X] Boolean '||'
- [X] Boolean '!'
- [X] '|>' pipe operator
- [X] '<|' pipe operator
- [X] '>>' prepend operator leaving the underlying structure unaffected
- [X] '>!' prepend operator changing the underlying structure
- [X] '<<' append operator leaving the underlying structure unaffected
- [X] '<!' append operator changing the underlying structure
- [ ] '?' operator to provide default values for null

# Control Statements

## Sequences

- [X] Add top-level support for expression sequences terminated with a semicolon
- [X] Add support for {... ; ... ; ...} to create a sequence of expressions 

## if

- [X] Add support for if expressions
- [X] The if guard succeeds if the expression is boolean and true.  It is synonymous with `guard == true`.  Equality does not fail if the values being compared are of different types.

## match

- [ ] Add support for match expressions

## while

- [X] Add support for a while loop
- [X] The while guard succeeds if the expression is boolean and true.  It is synonymous with `guard == true`.  Equality does not fail if the values being compared are of different types.

# Built-in Functions

- [ ] exit
    - [X] Basic function
    - [ ] If a non-integer is passed then print it to stderr and exit with 1
    - [ ] Add an option to print the entire stack trace as well
- [X] gc - which is actually a force gc
- [ ] import
    - [X] Basic function
    - [ ] Add a fatal option to the import function; this is default behavior
    - [ ] Add a non-fatal option
- [X] imports
- [X] int
- [X] len
- [X] milliTimestamp
- [X] print
- [X] println
- [ ] string with two forms - one raw and the other literal.  The default is literal.
- [X] typeof

# Library

## CLI

- [X] Implement based on Oak
- [X] Add support for flag + or - suffix to enable is disable.

## Test

- [X] Tidy up the guards once `!` has been implemented
- [X] Should a test fail then exit(1) otherwise exit(0) so that I can add into pipeline
- [ ] Fix: duration of the entire test suite is incorrectly calculated
- [X] Display the report after each suite rather than all at the end

# REPL Features

- [X] Add support for state in the REPL
- [ ] Add a `readline` like capability into the REPL
- [ ] Auto-import the following libraries into the REPL - Std, Str, FS.  Add an option to disable this.

# Chore Features

- [X] Add a github pipeline to continuously test the project
- [ ] Expand the pipeline to test against Linux and Mac OS
- [X] Place the AST under garbage collection.  At the moment it is not which makes AST memory management impossible.
- [ ] Add a string heap to store identifier names and field names.  This will reduce memory footprint and allow for faster comparisons.
- [X] On an error - display the line number and column number
- [X] When an error is reported, unwind the stack so that the error is reported in the full context of the caller
- [X] Record error position whenever an error is reported
