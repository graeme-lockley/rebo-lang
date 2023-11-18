Pattern matching is a wonderful way to write selection code in a concise descriptive manner.

It is possible to match unit values.  This technique is useful when you have a function that returns a value but uses `()` to indicate a non-value.

```rebo-repl
> match ()
. | () -> "unit"
. | _ -> "not unit"
"unit"

> match 1
. | () -> "unit"
. | _ -> "not unit"
"not unit"
```

Literal integer values can be matched as expected.

```rebo-repl
> match 1
. | 0 -> "zero"
. | 1 -> "one"
. | _ -> str(x)
"one"

> match 99
. | 0 -> "zero"
. | 1 -> "one"
. | x -> str(x)
"99"
```

Literal char values can be matched with the pattern matching supporting the 4 different char markups.

```rebo-repl
> let matchChar(c) =
.   match c
.   | 'a' -> "a"
.   | '\n' -> "newline"
.   | '\\' -> "backslash"
.   | '\'' -> "single-quote"
.   | '\x13' -> "linefeed"
.   | _ -> "other"

> matchChar('a')
"a"
> matchChar('b')
"other"
> matchChar('\n')
"newline"
> matchChar('\\')
"backslash"
> matchChar('\'')
"single-quote"
> matchChar('\x13')
"linefeed"
```

Like literal chars, literal string values can be matched with the pattern matching supporting the 4 different string markups.

```rebo-repl
> let matchString(s) =
.   match s
.   | "a" -> "a"
.   | "\n" -> "newline"
.   | "\\" -> "backslash"
.   | "'" -> "single-quote"
.   | "\"" -> "double-quote"
.   | "\x13;" -> "linefeed"
.   | "hello world" -> "greeting"
.   | _ -> "other"

> matchString("a")
"a"
> matchString("b")
"other"
> matchString("\n")
"newline"
> matchString("\\")
"backslash"
> matchString("'")
"single-quote"
> matchString("\"")
"double-quote"
> matchString("\x13;")
"linefeed"
> matchString("hello world")
"greeting"
```

For reasons of consistency, the pattern matching also supports matching literal boolean values and literal floats.

```rebo-repl
> let matchValue(v) =
.   match v
.   | true -> "true"
.   | false -> "false"
.   | 1.0 -> "one"
.   | 2.0 -> "two"
.   | _ -> "other"

> matchValue(true)
"true"
> matchValue(false)
"false"
> matchValue(1.0)
"one"
> matchValue(2.0)
"two"
> matchValue(3.0)
"other"
```

With pattern matching, int and float matching are interchangeable.

```rebo-repl
> let matchValue(v) =
.   match v
.   | 1 -> "one"
.   | 2.0 -> "two"
.   | _ -> "other"

> matchValue(1)
"one"
> matchValue(1.0)
"one"
> matchValue(2)
"two"
> matchValue(2.0)
"two"
```
