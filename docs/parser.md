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

## Assignment

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

## BinaryOp

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

## Call

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

## Catch

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

## Dot

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

## ID Declaration

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

## Identifier

```rebo-repl
> rebo.lang.parse("x")
{ kind: "exprs"
, value: 
  [ { kind: "identifier", value: "x" }
  ]
}
```

## If Then Else

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

## Index Range

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

## Index Value
  
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
