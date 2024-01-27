In Rebo the handling of scopes is novel because one has access to a scope and can manipulate it.

A scope is represented as a sequence of bindings where the first element in the sequence is the global scope, the second element is the module scope and the remaining elements are based on the rules of each of Rebo's different  expression constructs.

The height of a scope is the number of elements in the sequence.  The height of the global scope is 1, the height of the module scope is 2 and the height of a scope created by a function call is 3.

```rebo-repl
> scopeHeight(global())
1

> scopeHeight(module())
2

> scopeHeight(scope())
2
```

The width of a scope is the number of bindings in the scope.  The width of the global scope is the number of builtin bindings.  The width of the module scope is the number of bindings in the module.  The width of a scope created by a function call is the number of parameters plus the number bindings in the function's body to that point.  The width of a scope is accessed using `len`.

```rebo
> global() |> keys() |> sort()
 ["all", "ansi", "any", "close", "constant", "contains", "count", "cwd", "each", "eval", "exit", "fexists", "filter", "findFirst", "findLast", "firstIndexOf", "float", "gc", "global", "import", "int", "join", "keys", "lastIndexOf", "len", "listen", "ls", "map", "map2d", "max", "milliTimestamp", "min", "module", "open", "print", "println", "range", "read", "rebo", "reduce", "reduce2d", "reverse", "scope", "scopeHeight", "socket", "sort", "split", "str", "sum", "super", "typeof", "values", "write"]

> len(global())
53

> len(module())
0
```

The two code blocks above demonstrates that each code block is evaluated in its own module scope and, as such, the module scope is empty at the state of a code block.  Using this it is now possible to demonstrate how scopes are open and automatically closed during execution.


## Block

Whenever Rebo encounters a block it opens a new scope and evaluates the expressions in the block in that scope.  Once the block has been evaluated the scope is closed and the bindings are discarded.

```rebo-repl
> scopeHeight(scope())
2

> { scopeHeight(scope()) }
3
```

## If

The `if` guards and their actions are run in the same scope as the enclosing block.

```rebo-repl
> if scopeHeight(scope()) == 2 -> true | false
true

> if true -> scopeHeight(scope())
2

> if false -> 0 | scopeHeight(scope())
2
```

## While

The `while` guard and body are run in the same scope as the enclosing block.


```rebo-repl
> let result = true
> while typeof(result := scopeHeight(scope())) == "Bool" -> { }
> result
2

> let result = true
> while typeof(result) == "Bool" -> { result := scopeHeight(scope()) }
> result
2
```
