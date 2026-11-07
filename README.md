# Goose IDE

Um editor para escrever e rodar Goose no iPhone, com interpretador local. O app
não envia código para nenhum servidor.

## Estado atual

- App SwiftUI com editor monoespaçado, realce de sintaxe, barra de símbolos no
  teclado e exemplos prontos (Fibonacci, arrays, FizzBuzz, laços).
- Interpretador próprio em `Sources/GooseCore/`, dividido em lexer, parser,
  AST e runtime.
- Execução fora da thread principal, com limites de passos, profundidade de
  recursão e tamanho de saída para o app nunca travar.
- 19 testes unitários; as saídas esperadas foram geradas pelo compilador Goose
  oficial (v2026.4), então o interpretador é conferido contra a linguagem, não
  contra si mesmo.

### O que já funciona

`fn` e `recursive fn`, `let`/`var`, `if`/`else if`/`else` como expressão,
`while`, `for i in n`, `for x in array`, `break`/`continue`, `return`,
recursão, parâmetros sem tipo, operadores aritméticos/comparativos/lógicos,
larguras de inteiro (`u8 + 1` estoura em 8 bits), `as`/`as!`, arrays inline
com `push`/`pop`/`append`, `.len`/`.cap`, `print(...)` e `str(...)`.

### O que ainda falta

`struct`, `enum`, `match`, slices (`a[1..4]`, `^2`), referências
(`&x`, `Mark..&`), retorno de múltiplos valores, `defer` e a biblioteca padrão
(`json`, `regex`, `vec`...). O interpretador avisa com uma mensagem clara
quando encontra `struct`/`enum`/`import`/`const`.

## Executar o app

1. Abra `GooseIDE.xcodeproj` no Xcode em um Mac.
2. Selecione o scheme `GooseIDE` e um simulador de iPhone.
3. Execute com `Cmd+R`.

## Executar os testes

Em qualquer plataforma com Swift 5.9 ou mais recente:

```sh
swift test
```

## Exemplo suportado

```goose
recursive fn fib(n: i64) -> i64 {
    if n < 2 { return n; }
    return fib(n - 1) + fib(n - 2);
}

fn main() {
    for i in 10 { print("fib(", i, ") = ", fib(i)); }
}
```

Consulte a [linguagem Goose original](https://github.com/aardappel/goose) para
a especificação completa.
