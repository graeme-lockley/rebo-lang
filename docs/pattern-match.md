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
.   | stuff -> stuff |> map(fn(a) a * 10)

> matchSeq([1, 1, 3])
[10, 10, 30]
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
[10, 10, 20, 30]
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

Having worked through sequence pattern matching let's now take a look at record pattern matching.

```rebo-repl
> match {}
. | {} -> "empty"
. | _ -> "not empty"
"empty"

> match {a: 1}
. | {} -> "empty"
. | _ -> "not empty"
"empty"
```

Okay the last example was a bit of a  surprise.  The reason for this is to see record pattern matching as not an attempt at being exhaustive but rather as a way to match against a record that has a particular fields.

Using pattern matching is possible to bind values from the record.

```rebo-repl
> match {a: 1}
. | {a} -> a
. | _ -> 0
1

> match {a: 1, b: 2}
. | {a, b} -> a + b
. | _ -> 0
3
```

This style of pattern matching is useful when you want to match against a record that has a particular field but you don't care about the value of the field.  Using the `@` operator it is possible to bind the field to a different name.

```rebo-repl
> match {a: 1, b: 2}
. | {a @ xName, b @ yName} -> xName + yName
. | _ -> 0
3

> match {a: 1, b: 2}
. | {"a" @ xName, "b" @ yName} -> xName + yName
. | _ -> 0
3
```

It is also possible to match against a record that has a particular field and a particular value for that field.

```rebo-repl
> let matchRecord(r) =
.   match r
.   | {a: 2, b} -> b * 2
.   | {a: 1, b} -> b * 3
.   | {b} -> b * 4

> matchRecord({a: 1, b: 2})
6
> matchRecord({a: 2, b: 2})
4
> matchRecord({a: 10, b: 2})
8
> matchRecord({b: 2})
8
```

Let's bring it all together into a single example to show off record matching in all its wonder.

```rebo-repl
> let matchRecord(r) =
.   match r
.   | {a: {x, y}, b: [1, y']} -> x + 100 * (y + y')
.   | {a: {x, y}, b: [x', y']} -> x + x' + 100 * (x' + y')
.   | {a: {x, y}, b: [x', y'], c} -> x + x' + c * (x' + y')

> matchRecord({a: {x: 1, y: 2}, b: [1, 2]})
401
> matchRecord({a: {x: 1, y: 2}, b: [2, 3]})
503
> matchRecord({a: {x: 1, y: 2}, b: [2, 3], c: 100})
503
```

Note that should there be no match then an error is reported and your program halts.

