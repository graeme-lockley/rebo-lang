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

## DivideByZero

This error is raised when an attempt is made to divide by zero.

```rebo-repl
> let divide(x, y) = x / y

> divide(10, 0) catch { kind: "DivideByZero" } -> ()
()
```

## SyntaxError

This error is raised when the parser encounters a syntactic error.  This example of error is a little strange in that the expression is enclosed into an `eval` call.  This is because the parser, once it encounters an error, stops parsing and returns the error.

```rebo-repl
> eval("(10 /)") catch { kind: "SyntaxError" } -> ()
()
```
