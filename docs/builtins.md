Rebo has a number of builtin functions and values that are attached to the top-level scope.  These are the functions that are available to you without having to import anything.

**Note:** It is possible to redefine these functions in your own code, but this is not recommended.  For example, to replace `gc` so that it prints the duration of the garbage collection, you could do the following:

```rebo
let _gc = gc

gc := fn() {
   let stats = _gc()
   
   println("GC duration: ", stats.duration, "ms")

   stats
}

gc()
```

## eval(script, options = {})

`eval` allows you to evaluate a string as Rebo code.  This is useful for dynamically generating code, or for creating a REPL.  The options are as follows:

- `persistent = false`: If true, the code will be evaluated in the current scope.  If false, the code will be evaluated in a new scope and all declarations will not be visible outside of the expression.

```rebo-repl
> eval("let x = 1")
1

> x catch { kind: "UnknownIdentifierError"} -> ()
()

> eval("let x = 1", { persistent: false })
1

> x catch { kind: "UnknownIdentifierError"} -> ()
()

> eval("let y = 1", { persistent: true })
1

> y
1
```
