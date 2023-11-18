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

Now, this is where the fun starts - we are also able to match against sequences.  This pattern matching has different forms so it is best to work through these forms one by one.

Firstly we can match against a sequence of a fixed length.

```rebo-repl
> let matchSeq(seq) =
.   match seq
.   | [] -> "empty"
.   | [_] -> "one"
.   | [_, _] -> "two"
.   | [_, _, _] -> "three"
.   | _ -> "lots"

> matchSeq([])
"empty"
> matchSeq([1])
"one"
> matchSeq([1, 2])
"two"
> matchSeq([1, 2, 3])
"three"
> matchSeq([1, 2, 3, 4])
"lots"
```

We can also, using literal matching, combine literal values with sequences.

```rebo-repl
> let matchSeq(seq) =
.   match seq
.   | [1, 2, 3] -> "one two three"
.   | [1, 2, 3, 4] -> "one two three four"
.   | _ -> "other"

> matchSeq([1, 2, 3])
"one two three"
> matchSeq([1, 2, 3, 4])
"one two three four"
> matchSeq([1, 2, 3, 4, 5])
"other"
```

We can also use literal interspersed with identifiers in the sequence.

```rebo-repl
> let matchSeq(seq) =
.   match seq
.   | [1, x, 3] -> "one " + str(x) + " three"
.   | [1, x, 3, 4] -> "one " + str(x) + " three four"
.   | _ -> "other"

> matchSeq([1, 2, 3])
"one 2 three"
> matchSeq([1, "xxx", 3])
"one \"xxx\" three"
> matchSeq([1, "hello", 3, 4])
"one \"hello\" three four"
> matchSeq([1, 2, 3, 4, 5])
"other"
```

We can also use the `...` operator to match against a sequence of a minimum length.

```rebo-repl
> let matchSeq(seq) =
.   match seq
.   | [1, 2, 3, 4, ...] -> "one two three four ..."
.   | [1, 2, 3, ...] -> "one two three ..."
.   | _ -> "other"

> matchSeq([1, 2, 3])
"one two three ..."
> matchSeq([1, 2, 3, 4])
"one two three four ..."
> matchSeq([1, 2, 3, 4, 5])
"one two three four ..."
> matchSeq([1, 2, 3, 4, 5, 6])
"one two three four ..."
```

The `...` operator can also be used to bind the rest of the sequence to a value.

```rebo-repl
> let matchSeq(seq) =
.   match seq
.   | [1, 2, 3, 4, ...stuff] -> stuff
.   | [1, 2, 3, ...stuff] -> stuff
.   | stuff -> stuff

> matchSeq([1, 2, 3])
[]
> matchSeq([1, 2, 3, 4])
[]
> matchSeq([1, 2, 3, 3, 4])
[3, 4]
> matchSeq([1, 2, 3, 4, 5])
[5]
> matchSeq([1, 2, 3, 4, 5, 6])
[5, 6]
> matchSeq([1, 1, 2, 3])
[1, 1, 2, 3]
```

Finally the `@` operator can be used to bind a matched sequence to a value.

```rebo-repl
> let matchSeq(seq) =
.   match seq
.   | [1, 2, ...] @ stuff -> stuff
.   | _ -> []

> matchSeq([1, 2])
[1, 2]
> matchSeq([1, 2, 3])
[1, 2, 3]
> matchSeq([4, 3, 2, 1])
[]
```
