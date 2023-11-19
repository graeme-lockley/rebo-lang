Having seen the benefit of pattern matching, it is also possible to use pattern matching in a declaration.  Let's start with a simple example.

```rebo-repl
> let coordinate = [1.0, 2.0]
> let [x, y] = coordinate
[1, 2]

> x
1
> y
2
```

A pattern declaration has the full extent of pattern matching including no declaration at all.

```rebo-repl
> let 1 = 1
1
```

Of course, if the pattern matching is unsuccessful, then this is an error and the evaluation stops.

```rebo-repl
> let 1 = 2
```

A common use is to import specific functions.

```rebo-repl
> let {map} = import("std")

> [1, 2, 3] |> map(fn(n) n + 1)
[2, 3, 4]
```

Similarly it is possible to rename an import to avoid a name clash.

```rebo-repl
> let {map @ map'} = import("std")

> [1, 2, 3] |> map'(fn(n) n + 1)
[2, 3, 4]
```
