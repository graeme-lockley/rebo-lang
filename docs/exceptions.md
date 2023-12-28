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

Idiomatically, rather than returning a string as the exception message, we would return a record with the field `kind` for the exception message.  This allows the caller to pattern match on the exception and for the runtime system to populate the stack trace as a field called `stack`.  

```rebo-repl
> let head(lst) =
.    match lst
.    | [] -> raise { kind: "EmptyList" }
.    | [x, ...] -> x

> head([]) catch { kind: "EmptyList" } -> ()
()

> head([1, 2, 3]) catch _ -> ()
1
```

This is the next assertion to add

```
> head([]) catch { kind: "EmptyList", stack } -> stack
()
```
