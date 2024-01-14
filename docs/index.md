Rebo is a dynamically typed interpreted programming language.  It is a small language that I have put together for fun, learning and experimentation.  As an implementation it is constantly work in progress.

I love programming languages and the techniques required to implement them.  This is all the way from the front end parsing, type inference, type checking and code generation to the back end runtime.  The challenge though is to find an implementation that is sufficiently simple to understand and yet powerful enough that it can be used for learning and experimentation.

Rebo is such a language.

I use Rebo in my day-to-day work and it is a great language for scripting and prototyping new ideas.  The ideas behind Rebo are multiple and it would be remiss of me not to call out these influences particularly as I have borrowed heavily from them.  The following are Rebo's primary influences:

- [Oak](https://oaklang.org)
- [TypeScript](https://www.typescriptlang.org) running on [Deno](https://deno.com)
- [Elm](https://elm-lang.org)
- [Kotlin](https://kotlinlang.org)

Rebo itself has the following features:

- Dynamically typed,
- Strongly typed,
- Local and remote packages,
- First class functions,
- Pattern matching, and
- Unit, boolean, char, integer, float, string, function, sequence,  record types and files

The interpreter and runtime system is written in Zig however much of the library functions are written in Rebo.  As more and more is built out and the runtime system is optimised, the language semantics will be preserved.


# Core Language

Let's get started by getting a feeling for Rebo code.

The goal here is to become familiar with values, functions and control statements so you will be more confident reading Rebo code in the libraries, tools and demos.

All the code snippets in this section are valid Rebo code.  You can try them out in the [Rebo Playground](https://rebo-lang.org/playground) or using the Rebo REPL.  The REPL is a great way to experiment with Rebo code.

``` bash
$ rebo repl
> 
```

## Values

The smallest building block in Rebo is called a **value**.  A value is a piece of data that can be manipulated by a program.  There are 10 of different types of values in Rebo: unit, boolean, char, integer, float, string, function, sequence, record types, files and sockets.

Let's start by looking at the simplest value, the unit value.  The unit value is written as `()` and represents the absence of a value.  It is used in situations where a value is required but there is no value to provide.

```rebo-repl
> ()
()

> typeof(())
"Unit"
```

The `?` operator is used to provide an alternative value should the first value be `()`.

```rebo-repl
> () ? 10
10

> 11 ? 10
11
```

The boolean values are `true` and `false`.  They are used to represent the truth of a condition.

```rebo-repl
> true
true

> false
false

> typeof(true)
"Bool"
```

The customary operators `&&` and `||` are used to combine boolean values.

The char value is a single character.  It is written as `'c'` where `c` is any character.  Internally a char value is represented as an 8 bit unsigned byte.

```rebo-repl
> 'a'
'a'

> '1'
'1'

> typeof('a')
"Char"
```

There are 4 special forms that can be used as a char literal.

```rebo-repl
> int('\n')
10

> int('\\')
92

> int('\'')
39

> int('\x13')
13
```

The last special character is the escape character and used when special characters are needed in char literals.

An integer value is a whole number.  It is written as `n` where `n` is any whole number.  Internally an integer value is represented as a 64 bit signed integer.

```rebo-repl
> 10 + 3
13

> typeof(3)
"Int"
```

A float value is a decimal number.  It is written as `n.m` where `n` is any whole number and `m` is any whole number.  Internally a float value is represented as a 64 bit floating point number.

```rebo-repl
> 3.151
3.151

> 10 + 2.134
12.134

> typeof(3.151)
"Float"
```

A float value can also be written using scientific notation.

```rebo-repl
> 3.151e2
315.1

> 3.151e-2
0.03151
```

A string value is an immutable sequence of characters.  It is written as `"s"` where `s` is any sequence of characters.  Internally a string value is represented as a sequence of 8 bit unsigned bytes.

```rebo-repl
> "Hello World"
"Hello World"

> typeof("Hello World")
"String"
```

Like character, there are 4 special characters that can be used in a string literal.

```rebo-repl
> "Hello\n \\ \"World\""
"Hello\n \\ \"World\""

> "\x72;\x101;\x108;\x108;\x111;"
"Hello"
```

The `*` operator is used to repeat a string value.

```rebo-repl
> "" * 5
""

> "Hello " * 3
"Hello Hello Hello "

> len("x" * 100)
100

> len("x" * 0)
0
```

## Functions

A function value is a piece of code that can be executed.  It is written as `fn(args) = expr` where `args` is a comma separated list of arguments each with an optional default value and `expr` is an expression.  The `=` character used in the definition of a function is optional.  Idiomatically it is used when the function body is a single expression.

```rebo-repl
> let add = fn(a = 0, b = 1) = a + b
fn(a = 0, b = 1)

> add()
1

> add(10)
11

> add(10, 20)
30

> add(10, 20, 100)
30
```

The above definition for `add` is equivalent to the following.

```rebo-repl
> let add(a = 0, b = 1) = a + b
fn(a = 0, b = 1)
```

Should a parameter not be given a default it will default to `()`.

```rebo-repl
> let identity(x) = x
fn(x)

> identity(10)
10

> identity()
()
```

A function can also be declared with many parameters which are then passed as a sequence.

```rebo-repl
> let add(...args) = Std.reduce(args, fn(a, b) = a + b, 0)
fn(...args)

> add()
0

> add(10)
10

> add(1, 2, 3, 4, 5)
15
```

## If Expression

An `if` expression is used to support conditional behavior.  A definition of the Ackermann function would be a good example of this.

```rebo-repl
> let ackermann(m, n) = 
.   if m == 0 -> n + 1 
.    | n == 0 -> ackermann(m - 1, 1) 
.    | ackermann(m - 1, ackermann(m, n - 1))
fn(m, n)

> ackermann(1, 2)
4

> ackermann(2, 3)
9

> ackermann(3, 2)
29
```

## While Expression

A `while` expression is used to support looping behavior.  A definition of the factorial function would be a good example of this.

```rebo-repl
> let factorial(n) {
.   let result = 1
.   let i = 1
.   while i <= n -> {
.     result := result * i
.     i := i + 1
.   }
.   result
. }
fn(n)

> factorial(5)
120

> factorial(20)
2432902008176640000

> Std.range(11) |> Std.map(factorial)
[1, 1, 2, 6, 24, 120, 720, 5040, 40320, 362880, 3628800]
```

## Sequences

This structure is used to represent a sequence of values.  It is written as `[v1, v2, ...]` where `v1`, `v2`, etc are values.

```rebo-repl
> []
[]

> [1, 2, 3]
[1, 2, 3]

> typeof([1, 2, 3])
"Sequence"
```

The `[]` operator is used to access a value in a sequence.  The index is zero based.

```rebo-repl
> let seq = [1, 2, 3]
[1, 2, 3]

> seq[0]
1
```

A range can be used to access a subsequence of a sequence.  The range is written as `start:end` where `start` and `end` are integers.  The range is inclusive of `start` and exclusive of `end`.

```rebo-repl
> let seq = [1, 2, 3]
[1, 2, 3]

> seq[0:2]
[1, 2]
```

The `[]` operator can also be used to update a value in a sequence.

```rebo-repl
> let seq = [1, 2, 3]
[1, 2, 3]

> seq[0] := 10
10

> seq
[10, 2, 3]

> seq[1:2] := [100, 200, 300]
[100, 200, 300]

> seq
[10, 100, 200, 300, 3]
```

The `[]` operator can also be used to remove values from a sequence when assigning `()` to the range.

```rebo-repl
> let seq = [1, 2, 3, 4, 5]
[1, 2, 3, 4, 5]

> seq[1:3] := ()
()

> seq
[1, 4, 5]
```

The operators `<<` and `>>` are used to append and prepend a value onto to a sequence.

```rebo-repl
> let seq = [1, 2, 3]
[1, 2, 3]

> seq << 4
[1, 2, 3, 4]

> 0 >> seq
[0, 1, 2, 3]

> seq
[1, 2, 3]
```

As can be seen, the operators do not modify the sequence but return a new sequence. The operators `>!` and `<!` are used to modify the sequence.

```rebo-repl
> let seq = [1, 2, 3]
[1, 2, 3]

> seq <! 4
[1, 2, 3, 4]

> 0 >! seq
[0, 1, 2, 3, 4]

> seq
[0, 1, 2, 3, 4]
```

Finally, the `...` notation is used to create lists from existing lists.

```rebo-repl
> let seq = [1, 2, 3]
[1, 2, 3]

> [0, ...seq, 4]
[0, 1, 2, 3, 4]
```

## Records

A record is a collection of named values.  It is written as `{name1: v1, name2: v2, ...}` where `name1`, `name2` are names and `v1`, `v2` are values.

```rebo-repl
> let person = {name: "John", age: 20}
{name: "John", age: 20}

> typeof(person)
"Record"
```

The `.` operator is used to access a value in a record.

```rebo-repl
> let person = {name: "John", age: 20}
{name: "John", age: 20}

> person.name
"John"
```

The `.` operator can also be used to update a value in a record.

```rebo-repl
> let person = {name: "John", age: 20}
{name: "John", age: 20}

> person.name := "Jane"
"Jane"

> person
{name: "Jane", age: 20}
```

Like with sequences, the `...` operator can be used to create a new record from an existing record.

```rebo-repl
> let person = {name: "John", age: 20}
{name: "John", age: 20}

> let person2 = {...person, age: 21}
{name: "John", age: 21}

> person
{name: "John", age: 20}
```
