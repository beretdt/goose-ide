# Goose IDE

Um editor inicial para escrever e executar um subconjunto da linguagem Goose diretamente no iPhone. O app e o interpretador funcionam localmente; o projeto nao envia codigo para um servidor.

## Estado atual

- Projeto iOS nativo em SwiftUI, com editor de texto e painel de saida.
- Interpretador local inicial que entende `fn main()`, chamadas a `print(...)`, textos, numeros e booleanos.
- Testes unitarios para execucao, saida e erros de sintaxe.

Este ainda nao e um interpretador completo da linguagem Goose. Recursos como variaveis, expressoes, tipos, funcoes e arrays serao adicionados gradualmente.

## Executar o app

1. Abra `GooseIDE.xcodeproj` no Xcode em um Mac.
2. Selecione o scheme `GooseIDE` e um simulador de iPhone.
3. Execute com `Cmd+R`.

O app abre com um exemplo. Toque em **Executar** para ver a saida.

## Executar os testes

Em um Mac com Swift 5.9 ou mais recente:

```sh
swift test
```

## Exemplo suportado

```goose
fn main() {
    print("Hello, Goose!");
    print("A resposta e ", 42);
}
```

O interpretador atual aceita apenas essas formas de `print`. A sintaxe e intencionalmente limitada enquanto montamos a base; consulte a [linguagem Goose original](https://github.com/aardappel/goose) para a especificacao completa.
