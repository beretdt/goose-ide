# Goose IDE

Um editor para escrever e rodar Goose no iPhone, com interpretador local. O app
não envia código para nenhum servidor.

## Estado atual

- App SwiftUI com editor monoespaçado, realce de sintaxe, barra de símbolos no
  teclado e exemplos prontos (Fibonacci, arrays, structs, enums, slices,
  FizzBuzz, laços).
- Interpretador próprio em `Sources/GooseCore/`, dividido em lexer, parser,
  AST e runtime.
- Execução fora da thread principal, com limites de passos, profundidade de
  recursão e tamanho de saída para o app nunca travar.
- 31 testes unitários e 10 programas de referência. As saídas esperadas vêm do
  compilador Goose oficial (v2026.4), então o interpretador é conferido contra
  a linguagem, não contra si mesmo.

### O que já funciona

`fn` e `recursive fn`, `let`/`var`, `if`/`else if`/`else` como expressão,
`while`, `for i in n`, `for i in a..b`, `for x in array`, `break`/`continue`,
`return`, recursão, parâmetros sem tipo, operadores
aritméticos/comparativos/lógicos, larguras de inteiro (`u8 + 42` estoura em 8
bits e o literal adota a largura do outro operando), `as`/`as!`, arrays inline
com `push`/`pop`/`append`, `.len`/`.cap`, `print(...)` e `str(...)`.

Structs e enums:

- `struct` com campos tipados, defaults e literais posicionais ou nomeados;
  atribuição copia o valor, como em Goose.
- Aritmética elemento a elemento entre structs do mesmo tipo.
- `enum` com variantes que têm payload e variantes sem payload;
  `Shape.Circle { r: 1.0 }` e `Shape.Dot`.
- `match` como expressão, com bind do payload (`Circle c => c.r`), várias
  variantes por braço (`Circle, Dot => …`), literais, faixas (`1..50`) e `_`.

Slices: `a[1..4]`, `a[^2..]`, `a[..]`, `a[..2]`; aceitos por parâmetros
`T[:]` e por `for`.

### O que ainda falta

`import` e a biblioteca padrão (`std`, `vec`, `json`, `regex`…), optionais
(`T?`, `null` já existe mas `?` não), referências (`&x`), `T&`, `defer`,
`guard`, `block`, `loop`, retorno de múltiplos valores e `enum` em modo
variável (`Shape..`). O interpretador avisa com mensagem clara quando encontra
`import` ou `const`.

## Conferir contra o compilador oficial

`Tools/check_fidelity.sh` roda cada programa de `Tests/Fixtures/` nos dois
interpretadores e compara a saída:

```sh
swift build
GOOSE_REFERENCE=/caminho/para/goose Tools/check_fidelity.sh
```

`goosectl` (mesmo pacote) roda um arquivo solto:
`.build/debug/goosectl run programa.goose`.

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
