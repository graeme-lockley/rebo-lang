Pattern matching is a wonderful way to write selection code in a concise descriptive manner.

## Unit

It is possible to match unit values.  This technique is useful when you have a function that returns a value but uses `()` to indicate a non-value.

```rebo-repl
> let x = ()
> match x
. | () -> "unit"
. | _ -> "not unit"
"unit"

> let x = 1
> match x
. | () -> "unit"
. | _ -> "not unit"
"not unit"
```

## Integer
```rebo-repl
> let x = 1
> match x
. | 0 -> "zero"
. | 1 -> "one"
. | _ -> "other"
"one"
```
