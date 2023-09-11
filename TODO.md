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

- [ ] Let declaration
- [ ] Assignment without destructing
- [ ] Reference identifiers

## Functions

- [X] Add function literal
- [ ] Add function call
- [ ] Add function value

## Sequences

- [X] Add support for a literal sequence
- [ ] Add support for `...` when incorporating a literal sequence
- [ ] Add support for `[]` to access an element in a sequence based on value
- [ ] Add support for `[start:end]` to access a slice of sequence
- [ ] Add support for `[] = value` to update a sequence
- [ ] Add support for `[start:end] = value` to update a slice of sequence

## Strings

- [ ] Literal string without interpolation
- [ ] Literal string interpolation
- [ ] `[]` to access a char in a string
- [ ] `[start:end]` to access a slice of a string

## Records

- [ ] Add support for a literal record
- [ ] Add support for a literal string as a literal record field name
- [ ] Add support for `...` when incorporating a literal record
- [ ] Add support for `.field` to destruct a record
- [ ] Add support for `[]` to access a field in a record based on value
- [ ] Add support for `.field = value` to update a record

# Chore Features

- [X] Add a github pipeline to continuously test the project
- [ ] Expand the pipeline to test against Linux and Mac OS
- [ ] Place the AST under garbage collection.  At the moment it is not which makes AST memory management impossible.
