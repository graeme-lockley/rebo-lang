`rebo` starts up with a number of builtin functions and values attached to the variable `rebo`.  It should be noted that `rebo` is like any other global variable and can be redefined.

```rebo
> typeof(rebo)
"Record"

> rebo := "Hello World"
> typeof(rebo)
"String"
```

Redefining `rebo` is not recommended, but, as illustrated above, it is possible.

On startup `rebo` contains a number of categories of values of varying types:

```rebo-repl
> keys(rebo) |> sort()
[ "args", "env", "exe", "imports", "lang", "os" ]

> keys(rebo) |> sort() |> map(fn(k) [k, typeof(rebo[k])])
[["args", "Sequence"], ["env", "Record"], ["exe", "String"], ["imports", "Record"], ["lang", "Record"], ["os", "Record"]]
```

## `args`

`args` is a sequence of strings that contains the command line arguments passed to `rebo` when it was started.

```bash
$ cat show-args.rebo
println(rebo.args)

$ rebo show-args.rebo hello world
[rebo, show-args.rebo, hello, world]
```

**Note:** It is possible to mutate the sequence returned by `rebo.args` as it is a common old garden `rebo` sequence.`

## `env`

`env` is a record that contains the environment variables that were set when `rebo` was started.

```bash
$ cat show-env.rebo 
let Std = import("std")

keys(rebo.env) |> sort() |> each(fn(k) println(k, ": ", rebo.env[k]))

$ rebo show-env.rebo 
CPPFLAGS: -I/usr/local/opt/llvm/include
HOME: /Users/graemelockley
HOMEBREW_CELLAR: /usr/local/Cellar
HOMEBREW_PREFIX: /usr/local
HOMEBREW_REPOSITORY: /usr/local
JAVA_HOME: /Library/Java/JavaVirtualMachines/adoptopenjdk-12.jdk/Contents/Home
LC_CTYPE: UTF-8
LOGNAME: graemelockley
OLDPWD: /Users/graemelockley/Projects/rebo-lang
PATH: /usr/local/bin:/usr/local/sbin:/usr/local/bin:/System/Cryptexes/App/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/share/dotnet:~/.dotnet/tools:/Library/Apple/usr/bin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/local/bin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/bin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/appleinternal/bin:/Users/graemelockley/Projects/rebo-lang/bin
PWD: /Users/graemelockley/Projects/rebo-lang
SHELL: /bin/zsh
SHLVL: 1
TERM: xterm-256color
TERM_PROGRAM: Apple_Terminal
TERM_PROGRAM_VERSION: 447
TMPDIR: /var/folders/st/fcq136mx27x2s_5jvy9p2c840000gn/T/
USER: graemelockley
XPC_FLAGS: 0x0
XPC_SERVICE_NAME: 0
```

## `exe`

`exe` is a string that contains the path to the `rebo` executable.

```bash
$ cat show-exe.rebo
println(rebo.exe)

$ rebo show-exe.rebo
/Users/graemelockley/Projects/rebo-lang/bin/rebo-fast
```

## `imports`

`imports` is a record that contains the modules that have been imported into the current runtime.  The keys of the record are the names of the modules and the values are the modules themselves.

## `lang`

`lang` is a record that contains all of the builtin values and functions that collectively make up the `rebo` runtime system.

| Name | Type | Description |
| ---- | ---- | ----------- |
| `scope` | fn () | Returns the current scope. |
| `scope.bind!` | fn (`s: Scope`, `name: String`, `value: Any`) | Binds `value` to `name` in the passed scope. Should `name` already have a binding then it will be updated to `value`.  This function returns `value`. |
| `scope.open` | fn (`s: Scope`) | Opens a new scope with `s` as the parent to the result.  This function returns the new scope. |
| `scope.super` | fn (`s: Scope`) | Returns the super scope of the current scope. |
| `scope.super.assign!` | fn (`s: Scope`, `newParent: Scope`) | Makes `newParent` the super scope of `s`.  This function returns `s`. |

## `os`

`os` is a record that contains all of the builtin values and functions that allow rebo to access the operating system functions.

| Name | Type | Description |
| ---- | ---- | ----------- |
| `close` | fn (`fd: File \| Stream`) | Closes the file descriptor `fd`. |
| `cwd` | fn () | Returns the current working directory as a string. |
| `exit` | fn (`code: Int`) | Exits the current process with the exit code `code`. |
| `fexists` | fn (`name: String`) | Returns `true` if the object `name` exists on the file system.  Note that this function does not discriminate between files or directories and whether or not the object is readable. |

### eval(script, options = {})

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
