# rebo-lang

Rebo is a dynamically typed interpreted programming language. It is a work in progress.

I love tinkering around with programming languages trying to understand the techniques used to implement them.  I have been working on a number of projects in [little languages](https://github.com/littlelanguages) exploring these techniques.  Strangely enough, other than for Lisp, all of my efforts have been directed at statically typed languages.  I stumbled upon [Oak](https://oaklang.org) and was really impressed with what the author has achieved using a simple language and philosophy.  I decided to try my hand at a dynamically typed language.

Primary influences:

- [Oak](https://oaklang.org)
- [TypeScript](https://www.typescriptlang.org) running on [Deno](https://deno.com)
- [Elm](https://elm-lang.org)
- [Kotlin](https://kotlinlang.org)

Rebo itself has the following features:

- Indent based syntax,
- Dynamically typed,
- Local and remote packages,
- First class functions,
- Pattern matching,
- Unit, boolean, char, integer, float, string, function, sequence and record types, and
- Iteration through (tail) recursion.

The interpreter is written in Zig.

It is super early so, for now, star the project or periodically check back for updates.

## Examples

The first 1,000 prime numbers:

```
let { range } = import("std")
let { println } = import("io")

let prime?(n) = 
  let loop(i = 2) =
    if
    | i >= n / 2 -> true        
    | n % i == 0 -> false
    | true -> loop(i + 1)

  loop()

let primes(n) =
  range(2, n)
    |> filter(prime?)

println("The first 1000 prime numbers are: { primes(1000) }")
```

The following is the REST version of *hello world*.

```
let Fmt = import("fmt")
let HTTP = import("http")

let server = HTTP.Server()
server.route("/hello/:name") <| fn(params) =
    fn(req, end) =
      if req.method
      | "GET" -> end({
            status: 200,
            body: Fmt.format("Hello, { params.name ? "World" }!")
        })
      | _ -> end(HTTP.MethodNotAllowed)

server.start(9999)
```

## See also

- Where does the name "Rebo" come from?  I am an annoying Star Wars fan and it is a reference to the [Max Rebo Band](https://starwars.fandom.com/wiki/Max_Rebo_Band) from Return of the Jedi.

## Languages of interest

This list is of languages that I am keeping an eye on - they are interesting and I am curious to see how they evolve.

- [Gleam](https://gleam.run) is a strongly typed functional language that compiles to Erlang.

