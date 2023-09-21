There is so much to do.  The following is my work list on this project.  I will continuously juggle the sequence of these tasks as I work on them depending on what I would like to get working next.

# Language Features

## Literals:

- [X] Unit literal
- [X] Boolean literal
- [X] Integer literal
- [ ] Char literal
- [ ] Symbol literal
- [ ] Float literal

## Values

- [X] Let declaration
- [ ] Assignment without destructing
- [ ] Reference identifiers

## Functions

- [X] Add function literal
- [X] Add function call
- [X] Add function value
- [ ] Add support for ...argument to get the remainder of the arguments as a sequence

## Sequences

- [X] Add support for a literal sequence
- [ ] Add support for `...` when incorporating a literal sequence
- [ ] Add support for `[]` to access an element in a sequence based on value
- [ ] Add support for `[start:end]` to access a slice of sequence
- [ ] Add support for `[] = value` to update a sequence
- [ ] Add support for `[start:end] = value` to update a slice of sequence
- [ ] Add support destructuring a sequence into variables

## Strings

- [ ] Literal string without interpolation
- [ ] Literal string interpolation
- [ ] `[]` to access a char in a string
- [ ] `[start:end]` to access a slice of a string

## Records

- [X] Add support for a literal record
- [ ] Add support for a literal string as a literal record field name
- [ ] Add support for `...` when incorporating a literal record
- [X] Add support for `.field` to access a record's field
- [ ] Add support for `[]` to access a field in a record based on value
- [ ] Add support for `.field = value` to update a record
- [ ] Add support for destructing a record into variables

# Operators

- [X] Integer '+'
- [X] Integer '-'
- [X] Integer '*'
- [X] Integer '/'
- [ ] Integer '%'
- [ ] Real '+'
- [ ] Real '-'
- [ ] Real '*'
- [ ] Real '/'
- [X] Integer '=='
- [X] Integer '!='
- [ ] All '=='
- [ ] All '!='
- [ ] Integer '<'
- [ ] Integer '<='
- [ ] Integer '>'
- [ ] Integer '>='
- [ ] Real '<'
- [ ] Real '<='
- [ ] Real '>'
- [ ] Real '>='
- [ ] Boolean '&&'
- [ ] Boolean '||'
- [ ] Boolean '!'

# Control Statements

## Sequences

- [X] Add top-level support for expression sequences terminated with a semicolon
- [ ] Include this into the REPL
- [ ] Add support for (... ; ... ; ...) to create a sequence of statements 

## if

- [X] Add support for if expressions
- [ ] Include pattern machine into if expressions

# Chore Features

- [X] Add a github pipeline to continuously test the project
- [ ] Expand the pipeline to test against Linux and Mac OS
- [ ] Place the AST under garbage collection.  At the moment it is not which makes AST memory management impossible.
- [ ] Add a string heap to store identifier names and field names.  This will reduce memory footprint and allow for faster comparisons.
