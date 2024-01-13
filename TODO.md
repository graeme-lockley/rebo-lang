There is so much to do.  The following is my work list on this project.  I will continuously juggle the sequence of these tasks as I work on them depending on what I would like to get working next.

# Feature: Move `import` into user space

The first implementation of `import` was as a builtin which was perfect to get started.  However imports can be so much more.  For example, using [Scanpiler's](https://github.com/littlelanguages/scanpiler) notation, I can write a a lexical definition for a language and place it in the file `scanner.llex`.  It would be super cool to be able to use these definitions in my code with the following statement:

```rebo
let Scanner = import("scanner.llex", { tool: "./tools/scanpiler.rebo", cache: true })
```

This would import the lexical definitions from the file `scanner.llex` and compile them into a module called `Scanner`.  The `tool` option would be used to specify the path to the tool that would be used to compile the lexical definitions.  The `cache` option would be used to specify whether the compiled module should be cached or not.  If the `cache` option is `true` then the compiled module would be cached and the next time the `import` statement is executed, the cached module would be used instead of recompiling the lexical definitions.

Of course, we can up the ante with by allowing the `import` statement to import modules from the web.  For example, the following statement would import the lexical definitions from the file `scanner.llex` from the `littlelanguages` repository on GitHub:

```rebo
let Scanner = import("scanner.llex", { 
   tools: "https://raw.githubusercontent.com/littlelanguages/scanpiler/main/tools/scanpiler.rebo", 
   cache: true 
})
```

This is a very powerful feature that would allow `rebo` to be used to build a wide variety of tools and then attach them to the language using the `import` statement.  This feature supports the `rebo` principle of *Zero Configuration*.

## Tasks

- [ ] Move the collection of imported modules to `rebo.imports`


