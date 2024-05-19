# Parser

The rebo parser parsers a string and produces an Abstract Syntax Tree (AST).  The AST that is produced is used by all tools in the rebo ecosystem.

```rebo-repl
> rebo.lang.parse("1 + 2 * 3", { position: true })
{ kind: "exprs"
, value: 
  [ { kind: "binaryOp"
    , op: "+"
    , lhs: { kind: "literalInt", value: 1, position: [ 0, 1 ] }
    , rhs: 
      { kind: "binaryOp"
      , op: "*"
      , lhs: { kind: "literalInt", value: 2, position: [ 4, 5 ] }
      , rhs: { kind: "literalInt", value: 3, position: [ 8, 9 ] }
      , position: [ 4, 9 ]
      }
    , position: [ 0, 9 ]
    }
  ]
, position: [ 0, 9 ]
}
```

The littering of `position` fields in the AST is optional and, going through the different scenarios, it is best to not represent them as it creates loads of clutter.

```rebo-repl
> rebo.lang.parse("1 + 2 * 3")
{ kind: "exprs"
, value: 
  [ { kind: "binaryOp"
    , op: "+"
    , lhs: { kind: "literalInt", value: 1 }
    , rhs: 
      { kind: "binaryOp"
      , op: "*"
      , lhs: { kind: "literalInt", value: 2 }
      , rhs: { kind: "literalInt", value: 3 }
      }
    }
  ]
}
```

Now that we have the basic mechanism in place, let's systematically go through the different parts of the parser.

## Expressions

The following lists the different expression scenarios.

### Assignment

```rebo-repl
> rebo.lang.parse("x := 1")
{ kind: "exprs"
, value: 
  [ { kind: "assignment"
    , lhs: { kind: "identifier", value: "x" }
    , rhs: { kind: "literalInt", value: 1 }
    }
  ]
}
```

### BinaryOp

```rebo-repl
> rebo.lang.parse("1 - 2 / 3")
{ kind: "exprs"
, value: 
  [ { kind: "binaryOp"
    , op: "-"
    , lhs: { kind: "literalInt", value: 1 }
    , rhs: 
      { kind: "binaryOp"
      , op: "/"
      , lhs: { kind: "literalInt", value: 2 }
      , rhs: { kind: "literalInt", value: 3 }
      }
    }
  ]
}
```

### Call

```rebo-repl
> rebo.lang.parse("f(1, 2)")
{ kind: "exprs"
, value: 
  [ { kind: "call"
    , callee: { kind: "identifier", value: "f" }
    , args: 
      [ { kind: "literalInt", value: 1 }
      , { kind: "literalInt", value: 2 }
      ]
    }
  ]
}
```

### Catch

```rebo-repl
> rebo.lang.parse("10 catch e -> e")
{ kind: "exprs"
, value: 
  [ { kind: "catche"
    , value: { kind: "literalInt", value: 10 }
    , cases:
      [ { pattern: { kind: "identifier", value: "e" }
        , body: { kind: "identifier", value: "e" }
        }
      ]
    }
  ]
}
```

### Dot

```rebo-repl
> rebo.lang.parse("a.b")
{ kind: "exprs"
, value: 
  [ { kind: "dot"
    , record: { kind: "identifier", value: "a" }
    , field: "b"
    }
  ]
}
```

### ID Declaration

```rebo-repl
> rebo.lang.parse("let x = 1")
{ kind: "exprs"
, value: 
  [ { kind: "idDeclaration"
    , id: "x"
    , value: { kind: "literalInt", value: 1 }
    }
  ]
}
```

### Identifier

```rebo-repl
> rebo.lang.parse("x")
{ kind: "exprs"
, value: 
  [ { kind: "identifier", value: "x" }
  ]
}
```

### If Then Else

```rebo-repl
> rebo.lang.parse("if a -> 1 | b -> 2 | 3")
{ kind: "exprs"
, value: 
  [ { kind: "ifThenElse"
    , cases:
      [ { condition: { kind: "identifier", value: "a" }
        , then: { kind: "literalInt", value: 1 }
        }
      , { condition: { kind: "identifier", value: "b" }
        , then: { kind: "literalInt", value: 2 }
        }
      , { then: { kind: "literalInt", value: 3 }
        }
      ]
    }
  ]
}
```

### Index Range

```rebo-repl
> rebo.lang.parse("a[1:2]")
{ kind: "exprs"
, value: 
  [ { kind: "indexRange"
    , expr: { kind: "identifier", value: "a" }
    , start: { kind: "literalInt", value: 1 }
    , end: { kind: "literalInt", value: 2 }
    }
  ]
}

> rebo.lang.parse("a[:2]")
{ kind: "exprs"
, value: 
  [ { kind: "indexRange"
    , expr: { kind: "identifier", value: "a" }
    , end: { kind: "literalInt", value: 2 }
    }
  ]
}

> rebo.lang.parse("a[1:]")
{ kind: "exprs"
, value: 
  [ { kind: "indexRange"
    , expr: { kind: "identifier", value: "a" }
    , start: { kind: "literalInt", value: 1 }
    }
  ]
}

> rebo.lang.parse("a[:]")
{ kind: "exprs"
, value: 
  [ { kind: "indexRange"
    , expr: { kind: "identifier", value: "a" }
    }
  ]
}
```

### Index Value
  
```rebo-repl
> rebo.lang.parse("a[1]")
{ kind: "exprs"
, value: 
  [ { kind: "indexValue"
    , expr: { kind: "identifier", value: "a" }
    , index: { kind: "literalInt", value: 1 }
    }
  ]
}
```

### Literal Bool

```rebo-repl
> rebo.lang.parse("true")
{ kind: "exprs"
, value: 
  [ { kind: "literalBool", value: true }
  ]
}
```

### Literal Char

```rebo-repl
> rebo.lang.parse("'a'")
{ kind: "exprs"
, value: 
  [ { kind: "literalChar", value: 'a' }
  ]
}
```

### Literal Function

```rebo-repl
> rebo.lang.parse("fn() 1")
{ kind: "exprs"
, value: 
  [ { kind: "literalFunction"
    , params: []
    , body: { kind: "literalInt", value: 1 }
    }
  ]
}

> rebo.lang.parse("fn(a) a")
{ kind: "exprs"
, value: 
  [ { kind: "literalFunction"
    , params: 
      [ { name: "a" }
      ]
    , body: { kind: "identifier", value: "a" }
    }
  ]
}

> rebo.lang.parse("fn(a = 10) a")
{ kind: "exprs"
, value: 
  [ { kind: "literalFunction"
    , params: 
      [ { name: "a" 
        , default: { kind: "literalInt", value: 10 }
        }
      ]
    , body: { kind: "identifier", value: "a" }
    }
  ]
}

> rebo.lang.parse("fn(a = 10, ...rest) rest << a")
{ kind: "exprs"
, value: 
  [ { kind: "literalFunction"
    , params: 
      [ { name: "a" 
        , default: { kind: "literalInt", value: 10 }
        }
      ]
    , restOfParams: "rest"
    , body: 
      { kind: "binaryOp"
      , op: "<<"
      , lhs: { kind: "identifier", value: "rest" }
      , rhs: { kind: "identifier", value: "a" }
      }
    }
  ]
}
```

### Literal Int

```rebo-repl
> rebo.lang.parse("10")
{ kind: "exprs"
, value: 
  [ { kind: "literalInt", value: 10 }
  ]
}
```


### Literal Float

```rebo-repl
> rebo.lang.parse("10.0")
{ kind: "exprs"
, value: 
  [ { kind: "literalFloat", value: 10.0 }
  ]
}
```

### Literal Record

```rebo-repl
> rebo.lang.parse("{ a: 1, b: 2 }")
{ kind: "exprs"
, value: 
  [ { kind: "literalRecord"
    , fields: 
      [ { kind: "value", key: "a", value: { kind: "literalInt", value: 1 } }
      , { kind: "value", key: "b", value: { kind: "literalInt", value: 2 } }
      ]
    }
  ]
}

> rebo.lang.parse("{ ...x, a: 1, ...y, b: 2 }")
{ kind: "exprs"
, value: 
  [ { kind: "literalRecord"
    , fields: 
      [ { kind: "record", value: { kind: "identifier", value: "x" } }
      , { kind: "value", key: "a", value: { kind: "literalInt", value: 1 } }
      , { kind: "record", value: { kind: "identifier", value: "y" } }
      , { kind: "value", key: "b", value: { kind: "literalInt", value: 2 } }
      ]
    }
  ]
}
```

### Literal Sequence

```rebo-repl
> rebo.lang.parse("[1, 2, 3]")
{ kind: "exprs"
, value:
  [ { kind: "literalSequence"
    , values: 
      [ { kind: "value", value: { kind: "literalInt", value: 1 } }
      , { kind: "value", value: { kind: "literalInt", value: 2 } }
      , { kind: "value", value: { kind: "literalInt", value: 3 } }
      ]
    }
  ]
}

> rebo.lang.parse("[...x, 1, ...y, 2, 3]")
{ kind: "exprs"
, value:
  [ { kind: "literalSequence"
    , values: 
      [ { kind: "sequence", value: { kind: "identifier", value: "x" } }
      , { kind: "value", value: { kind: "literalInt", value: 1 } }
      , { kind: "sequence", value: { kind: "identifier", value: "y" } }
      , { kind: "value", value: { kind: "literalInt", value: 2 } }
      , { kind: "value", value: { kind: "literalInt", value: 3 } }
      ]
    }
  ]
}
```

### Literal String

```rebo-repl
> rebo.lang.parse("\"hello\"")
{ kind: "exprs"
, value: 
  [ { kind: "literalString", value: "hello" }
  ]
}
```

### Literal Unit

```rebo-repl
> rebo.lang.parse("()")
{ kind: "exprs"
, value: 
  [ { kind: "literalUnit" }
  ]
}
```

### Match

```rebo-repl
> rebo.lang.parse("match 10 | 10 -> 1 | 20 -> 2 | _ -> 3")
{ kind: "exprs"
, value: 
  [ { kind: "match"
    , value: { kind: "literalInt", value: 10 }
    , cases:
      [ { pattern: { kind: "literalInt", value: 10 }
        , body: { kind: "literalInt", value: 1 }
        }
      , { pattern: { kind: "literalInt", value: 20 }
        , body: { kind: "literalInt", value: 2 }
        }
      , { pattern: { kind: "identifier", value: "_" }
        , body: { kind: "literalInt", value: 3 }
        }
      ]
    }
  ]
}
```

### Not UnaryOp

```rebo-repl
> rebo.lang.parse("!true")
{ kind: "exprs"
, value: 
  [ { kind: "not"
    , expr: { kind: "literalBool", value: true }
    }
  ]
}
```

### Pattern Declaration

```rebo-repl
> rebo.lang.parse("let [a, b] = [1, 2]")
{ kind: "exprs"
, value: 
  [ { kind: "patternDeclaration"
    , pattern: 
      { kind: "sequence"
      , values: 
        [ { kind: "identifier", value: "a" }
        , { kind: "identifier", value: "b" }
        ]
      }
    , value: 
      { kind: "literalSequence"
      , values: 
        [ { kind: "value", value: { kind: "literalInt", value: 1 } }
        , { kind: "value", value: { kind: "literalInt", value: 2 } }
        ]
      }
    }
  ]
}

> rebo.lang.parse("let [a, b, ...c] @ d = [1, 2]")
{ kind: "exprs"
, value: 
  [ { kind: "patternDeclaration"
    , pattern: 
      { kind: "sequence"
      , values: 
        [ { kind: "identifier", value: "a" }
        , { kind: "identifier", value: "b" }
        ]
      , restOfPatterns: "c"
      , id: "d"
      }
    , value: 
      { kind: "literalSequence"
      , values: 
        [ { kind: "value", value: { kind: "literalInt", value: 1 } }
        , { kind: "value", value: { kind: "literalInt", value: 2 } }
        ]
      }
    }
  ]
}
```

### Raise

```rebo-repl
> rebo.lang.parse("raise 10")
{ kind: "exprs"
, value: 
  [ { kind: "raise"
    , expr: { kind: "literalInt", value: 10 }
    }
  ]
}
```

### While

```rebo-repl
> rebo.lang.parse("while true -> 1")
{ kind: "exprs"
, value: 
  [ { kind: "while"
    , condition: { kind: "literalBool", value: true }
    , body: { kind: "literalInt", value: 1 }
    }
  ]
}
```

## Patterns

There are a few different patterns that can be used in the language.  The following is a list of each of the different pattern scenarios.

### Identifier

```rebo-repl
> rebo.lang.parse("match 1 | x -> x")
{ kind: "exprs"
, value: 
  [ { kind: "match"
    , value: { kind: "literalInt", value: 1 }
    , cases:
      [ { pattern: { kind: "identifier", value: "x" }
        , body: { kind: "identifier", value: "x" }
        }
      ]
    }
  ]
}
```

### Literal Bool

```rebo-repl
> rebo.lang.parse("match x | true -> x")
{ kind: "exprs"
, value: 
  [ { kind: "match"
    , value: { kind: "identifier", value: "x" }
    , cases:
      [ { pattern: { kind: "literalBool", value: true }
        , body: { kind: "identifier", value: "x" }
        }
      ]
    }
  ]
}
```

### Literal Char

```rebo-repl
> rebo.lang.parse("match x | 'a' -> x")
{ kind: "exprs"
, value: 
  [ { kind: "match"
    , value: { kind: "identifier", value: "x" }
    , cases:
      [ { pattern: { kind: "literalChar", value: 'a' }
        , body: { kind: "identifier", value: "x" }
        }
      ]
    }
  ]
}
```

### Literal Float

```rebo-repl
> rebo.lang.parse("match x | 10.0 -> x")
{ kind: "exprs"
, value: 
  [ { kind: "match"
    , value: { kind: "identifier", value: "x" }
    , cases:
      [ { pattern: { kind: "literalFloat", value: 10.0 }
        , body: { kind: "identifier", value: "x" }
        }
      ]
    }
  ]
}
```

### Literal Int

```rebo-repl
> rebo.lang.parse("match x | 10 -> x")
{ kind: "exprs"
, value: 
  [ { kind: "match"
    , value: { kind: "identifier", value: "x" }
    , cases:
      [ { pattern: { kind: "literalInt", value: 10 }
        , body: { kind: "identifier", value: "x" }
        }
      ]
    }
  ]
}
```

### Literal String

```rebo-repl
> rebo.lang.parse("match x | \"hello\" -> x")
{ kind: "exprs"
, value: 
  [ { kind: "match"
    , value: { kind: "identifier", value: "x" }
    , cases:
      [ { pattern: { kind: "literalString", value: "hello" }
        , body: { kind: "identifier", value: "x" }
        }
      ]
    }
  ]
}
```

### Literal Unit

```rebo-repl
> rebo.lang.parse("match x | () -> x")
{ kind: "exprs"
, value: 
  [ { kind: "match"
    , value: { kind: "identifier", value: "x" }
    , cases:
      [ { pattern: { kind: "literalUnit" }
        , body: { kind: "identifier", value: "x" }
        }
      ]
    }
  ]
}
```

### Record

```rebo-repl
> rebo.lang.parse("match x | { a, b } -> x")
{ kind: "exprs"
, value: 
  [ { kind: "match"
    , value: { kind: "identifier", value: "x" }
    , cases:
      [ { pattern: 
          { kind: "record"
          , fields: 
            [ { key: "a" }
            , { key: "b" }
            ]
          }
        , body: { kind: "identifier", value: "x" }
        }
      ]
    }
  ]
}

> rebo.lang.parse("match x | { a: 1, b } -> x")
{ kind: "exprs"
, value: 
  [ { kind: "match"
    , value: { kind: "identifier", value: "x" }
    , cases:
      [ { pattern: 
          { kind: "record"
          , fields: 
            [ { key: "a", pattern: { kind: "literalInt", value: 1 } }
            , { key: "b" }
            ]
          }
        , body: { kind: "identifier", value: "x" }
        }
      ]
    }
  ]
}

> rebo.lang.parse("match x | { a: 1, b @ c} @ y -> x")
{ kind: "exprs"
, value: 
  [ { kind: "match"
    , value: { kind: "identifier", value: "x" }
    , cases:
      [ { pattern: 
          { kind: "record"
          , fields: 
            [ { key: "a", pattern: { kind: "literalInt", value: 1 } }
            , { key: "b", id: "c" }
            ]
          , id: "y"
          }
        , body: { kind: "identifier", value: "x" }
        }
      ]
    }
  ]
}
```

### Sequence

```rebo-repl
> rebo.lang.parse("match x | [a, b] -> x")
{ kind: "exprs"
, value: 
  [ { kind: "match"
    , value: { kind: "identifier", value: "x" }
    , cases:
      [ { pattern: 
          { kind: "sequence"
          , values: 
            [ { kind: "identifier", value: "a" }
            , { kind: "identifier", value: "b" }
            ]
          }
        , body: { kind: "identifier", value: "x" }
        }
      ]
    }
  ]
}

> rebo.lang.parse("match x | [a, b, ...c] -> x")
{ kind: "exprs"
, value: 
  [ { kind: "match"
    , value: { kind: "identifier", value: "x" }
    , cases:
      [ { pattern: 
          { kind: "sequence"
          , values: 
            [ { kind: "identifier", value: "a" }
            , { kind: "identifier", value: "b" }
            ]
          , restOfPatterns: "c"
          }
        , body: { kind: "identifier", value: "x" }
        }
      ]
    }
  ]
}

> rebo.lang.parse("match x | [a, b, ...c] @ d -> x")
{ kind: "exprs"
, value: 
  [ { kind: "match"
    , value: { kind: "identifier", value: "x" }
    , cases:
      [ { pattern: 
          { kind: "sequence"
          , values: 
            [ { kind: "identifier", value: "a" }
            , { kind: "identifier", value: "b" }
            ]
          , restOfPatterns: "c"
          , id: "d"
          }
        , body: { kind: "identifier", value: "x" }
        }
      ]
    }
  ]
}
```
