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

The interpreter and runtime system is written in Zig however as much of the library functions are written in Rebo.  As more and more is built out and the runtime system is optimised, the language semantics will be preserved.


# Core Language

Let's get started by getting a feeling for Rebo code.

The goal here is to become familiar with values, functions and control statements so you will be more confident reading Rebo code in the libraries, tools and demos.

All the code snippets in this section are valid Rebo code.  You can try them out in the [Rebo Playground](https://rebo-lang.org/playground) or using the Rebo REPL.  The REPL is a great way to experiment with Rebo code.

``` bash
$ rebo repl
> 
```

## Values

The smallest building block in Rebo is called a **value**.  A value is a piece of data that can be manipulated by a program.  There are 10 of different types of values in Rebo: unit, boolean, char, integer, float, string, function, sequence,  record types and files.

Let's start by looking at the simplest value, the unit value.  The unit value is written as `()` and represents the absence of a value.  It is used in situations where a value is required but there is no value to provide.

``` rebo
> ()
()

> typeof(())
"Unit"
```

The `?` operator is used to provide an alternative value should the first value be `()`.

``` rebo
> () ? 10
10

> 11 ? 10
11
```

The boolean values are `true` and `false`.  They are used to represent the truth of a condition.

``` rebo
> true
true

> false
false

> typeof(true)
"Bool"
```

The customary operators `&&` and `||` are used to combine boolean values.

The char value is a single character.  It is written as `'c'` where `c` is any character.  Internally a char value is represented as an 8 bit unsigned byte.

``` rebo
> 'a'
'a'

> '1'
'1'

> typeof('a')
"Char"
```

There are 3 special characters that can be used is a char literal.

```rebo
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

```rebo
> 10 + 3
13

> typeof(3)
"Int"
```

A float value is a decimal number.  It is written as `n.m` where `n` is any whole number and `m` is any whole number.  Internally a float value is represented as a 64 bit floating point number.

```rebo
> 3.151
3.151

> 10 + 2.134
12.134

> typeof(3.151)
"Float"
```

A float value can also be written using scientific notation.

```rebo
> 3.151e2
315.1

> 3.151e-2
0.03151
```

A string value is a sequence of characters.  It is written as `"s"` where `s` is any sequence of characters.  Internally a string value is represented as a sequence of 8 bit unsigned bytes.

```rebo
> "Hello World"
"Hello World"

> typeof("Hello World")
"String"
```

Like character, there are 3 special characters that can be used is a string literal.

```rebo
> "Hello\n\"World\""
"Hello\n\"World\""

> "\x72;\x101;\x108;\x108;\x111;"
"Hello"
```

A function value is a piece of code that can be executed.  It is written as `fn(args) = expr` where `args` is a comma separated list of arguments each with an optional default value and `expr` is an expression.  The `=` character used in the definition of a function is optional.  Idiomatically it is used when the function body is a single expression.

```rebo
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

```rebo
> let add(a = 0, b = 1) = a + b
fn(a = 0, b = 1)
```

Should a parameter not be given a default it will default to `()`.

```rebo
> let identity(x) = x
fn(x)

> identity(10)
10

> identity()
()
```

A function can also be declared with many parameters which are then passed as a sequence.

```
> let add(...args) = Std.reduce(args, fn(a, b) = a + b, 0)
fn(...args)

> add()
0

> add(10)
10

> add(1, 2, 3, 4, 5)
15
```
