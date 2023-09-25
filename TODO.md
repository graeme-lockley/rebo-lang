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
- [ ] Add support for `...` argument to get the remainder of the arguments as a sequence

## Sequences

- [X] Add support for a literal sequence
- [ ] Add support for `...` when incorporating a literal sequence
- [X] Add support for `[]` to access an element in a sequence based on value
- [X] Add support for `[start:end]` to access a slice of sequence
- [X] Add support for `[] = value` to update a sequence
- [ ] Add support for `[start:end] = value` to update a slice of sequence
- [X] `+` concatenates two sequences
- [ ] Add support destructuring a sequence into variables
- [ ] Move all the functions into the SequenceKind rather than having them lying all over the code base and forcing knowledge of the implementation

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
- [ ] Add support for `...` when incorporating a literal record
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
- [ ] Boolean '!'

# Control Statements

## Sequences

- [X] Add top-level support for expression sequences terminated with a semicolon
- [X] Add support for {... ; ... ; ...} to create a sequence of expressions 

## if

- [X] Add support for if expressions

## match

- [ ] Add support for match expressions

# Built-in Functions

- [ ] import

# REPL Features

- [ ] Add support for state in the REPL
- [ ] Add a `readline` like capability into the REPL

# Chore Features

- [X] Add a github pipeline to continuously test the project
- [ ] Expand the pipeline to test against Linux and Mac OS
- [ ] Place the AST under garbage collection.  At the moment it is not which makes AST memory management impossible.
- [ ] Add a string heap to store identifier names and field names.  This will reduce memory footprint and allow for faster comparisons.
