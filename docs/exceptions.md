Exceptions are a way to handle errors in your code.  An exception can be raised when something goes wrong and caught by the caller to recover from the exceptional condition in a predictable way.

Firstly let's take a look at a simple example of an exception being raised and caught.

```rebo-repl
> let head(lst) =
.    match lst
.    | [] -> raise "EmptyList"
.    | [x, ...] -> x

> head([]) catch _ -> ()
()

> head([1, 2, 3]) catch _ -> ()
1
```

In the above example we define a function `head` which takes a list and returns the first element of the list.  If the list is empty we raise an exception with the message "EmptyList".  We then call the function with an empty list and catch the exception.  The catch block is executed and the result of the catch block is returned.  In this case we return `()`.

Idiomatically, rather than returning a string as the exception message, we return a record with the field `kind` for the exception message.  This allows the caller to pattern match on the exception and for the runtime system to populate the stack trace as a field called `stack`.  

```rebo-repl
> let head(lst) =
.    match lst
.    | [] -> raise { kind: "EmptyList" }
.    | [x, ...] -> x

> head([]) catch { kind: "EmptyList" } -> ()
()

> head([1, 2, 3]) catch _ -> ()
1

> head([]) catch { kind: "EmptyList", stack } -> stack |> Std.map(fn (x) { ...x, file: "foo.rebo" })
[ { from: {line: 7, offset: 162, column: 19}, to: {line: 7, offset: 170, column: 26}, file: "foo.rebo" } ]
```

In the last example I change all of the file names in the stack to `foo.rebo` as the actual name is fully qualified and will differ from system to system depending on where this file is located.

There are some standard errors that are raised in the runtime system.  These errors are layed out through code examples.

## DivideByZeroError

This error is raised when an attempt is made to divide by zero.

```rebo-repl
> let divide(x, y) = x / y

> divide(10, 0) catch { kind: "DivideByZeroError" } @ err -> {...err, stack: []}
{ kind: "DivideByZeroError", stack: [] }

> divide(10.0, 0) catch { kind: "DivideByZeroError" } -> ()
()

> divide(10, 0.0) catch { kind: "DivideByZeroError" } -> ()
()

> divide(10.0, 0.0) catch { kind: "DivideByZeroError" } -> ()
()
```

## ExpectedTypeError

This error is raised when an expression is of the wrong type.

```rebo-repl
> [1, 2, 3].head catch { kind: "ExpectedTypeError" } @ err -> {...err, stack: []}
{ kind: "ExpectedTypeError", expected: ["Record"], found: "Sequence", stack: [] }

> ([1, 2, 3].head := 0) catch { kind: "ExpectedTypeError" } @ err -> {...err, stack: []}
{ kind: "ExpectedTypeError", expected: ["Record"], found: "Sequence", stack: [] }

> [1, 2, ...10] catch { kind: "ExpectedTypeError" } @ err -> {...err, stack: []}
{ kind: "ExpectedTypeError", expected: ["Sequence"], found: "Int", stack: [] }

> {a: 1, b: 2, ...10} catch { kind: "ExpectedTypeError" } @ err -> {...err, stack: []}
{ kind: "ExpectedTypeError", expected: ["Record"], found: "Int", stack: [] }

> (!10) catch { kind: "ExpectedTypeError" } @ err -> {...err, stack: []}
{ kind: "ExpectedTypeError", expected: ["Bool"], found: "Int", stack: [] }
```

## FunctionValueExpectedError

This error is a syntactic error and is raised with the operators `|>` and `<|` are not passed function invocations.  As this is a syntactic error, the expression is enclosed in an `eval` call as parsing stops as soon as this error is encountered.

```rebo-repl
> eval("10 |> 10") catch { kind: "FunctionValueExpectedError" } @ err -> {...err, stack: []}
{ kind: "FunctionValueExpectedError", content: "10 |> 10", stack: [] }

> eval("10 <| 10") catch { kind: "FunctionValueExpectedError" } @ err -> {...err, stack: []}
{ kind: "FunctionValueExpectedError", content: "10 <| 10", stack: [] }
```

## IncompatibleOperandTypesError

This error is raised when an attempt is made to perform an operation on operands of incompatible types.

```rebo-repl
> (10 + "hello") catch { kind: "IncompatibleOperandTypesError" } @ err -> {...err, stack: []}
{ kind: "IncompatibleOperandTypesError", op: "+", left: "Int", right: "String", stack: [] }
```

## IndexOfOutRangeError

This error is raised when an attempt is made to assign a value to a list based on an index which is out of range.

```rebo-repl
> ([1, 2, 3][10] := 1) catch { kind: "IndexOutOfRangeError" } @ err -> {...err, stack: []}
{ kind: "IndexOutOfRangeError", index: 10, lower: 0, upper: 3, stack: [] }

> ([1, 2, 3][-1] := 1) catch { kind: "IndexOutOfRangeError" } @ err -> {...err, stack: []}
{ kind: "IndexOutOfRangeError", index: -1, lower: 0, upper: 3, stack: [] }
```

## InvalidLHSError

This error is raised when an attempt is made to assign to a value that is not a variable.

```rebo-repl
> (10 := 11) catch { kind: "InvalidLHSError" } @ err -> {...err, stack: []}
{ kind: "InvalidLHSError", stack: [] }
```

## LexicalError

This error is raised when the scanner encounters a lexical error.  This example of error is a little strange in that the expression is enclosed into an `eval` call.  This is because the scanner, once it encounters an error, stops scanning and returns the error.

```rebo-repl
> eval("10 / ^") catch { kind: "LexicalError" } @ err -> {...err, stack: []}
{ kind: "LexicalError", found: "", content: "10 / ^", stack: [] }
```

## LiteralIntOverFlowError

This error is raised when an integer point literal is too large to be represented.  This example of error is a little strange in that the expression is enclosed into an `eval` call.  This is because the parser, once it encounters an overflow, stops parsing and returns the error.

```rebo-repl
> eval("1 + 10000000000000000000000000") catch { kind: "LiteralIntOverflowError" } @ err -> {...err, stack: []}
{ kind: "LiteralIntOverflowError", value: "10000000000000000000000000", content: "1 + 10000000000000000000000000", stack: [] }
```

## MatchError

This error is raised when a match expression fails to match any of the patterns.

```rebo-repl
> (match 10 | 0 -> 0) catch { kind: "MatchError" } @ err -> {...err, stack: []}
{ kind: "MatchError", value: 10, stack: [] }

> (let [a, b] = 10) catch { kind: "MatchError" } @ err -> {...err, stack: []}
{ kind: "MatchError", value: 10, stack: [] }
```

## SyntaxError

This error is raised when the parser encounters a syntactic error.  This example of error is a little strange in that the expression is enclosed into an `eval` call.  This is because the parser, once it encounters an error, stops parsing and returns the error.

```rebo-repl
> eval("(10 /)") catch { kind: "SyntaxError" } @ err -> {...err, stack: []}
{ kind: "SyntaxError", found: ")", expected: ["'['", "'{'", "identifier", "'('", "false", "true", "literal char", "literal float", "literal int", "literal string", "fn"], content: "(10 /)", stack: [] }
```

## UnknownIdentifierError

This error is raised when the interpreter encounters an unknown identifier.

```rebo-repl
> x catch { kind: "UnknownIdentifierError" } @ err-> {...err, stack: []}
{ kind: "UnknownIdentifierError", identifier: "x", stack: [] }
```
