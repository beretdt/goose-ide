# Goose IDE

Um editor para escrever e rodar Goose no iPhone, com interpretador local. O app
não envia código para nenhum servidor.

## Estado atual

O núcleo do app é **executar Goose**: o interpretador roda no aparelho, offline,
e é conferido contra o compilador oficial em cada construção.

- App SwiftUI com tema VS Code Dark+, editor com numeração de linhas, barra de
  símbolos no teclado e exemplos prontos.
- Interpretador próprio em `Sources/GooseCore/` (lexer, parser, AST, runtime).
- Execução fora da thread principal, com limites de passos, profundidade e
  saída para o app nunca travar.
- GitHub: abrir um `.goose` de um repositório e commitar pelo iPhone.
- Agente de IA opcional (OpenRouter, GitHub Models ou endpoint compatível) que
  escreve no editor ao vivo.
- **67 testes** (46 do interpretador, 15 do cliente GitHub, 21 do cliente de IA)
  e **14 programas de referência**. As saídas esperadas vêm do compilador Goose
  oficial (v2026.4), então o interpretador é comparado com a linguagem, não
  consigo mesmo.

### O que a linguagem já executa

Declarações e funções:

- `fn` e `recursive fn` (obrigatório antes de recursão), parâmetros tipados ou
  sem tipo, `return` com um ou vários valores.
- `let` / `var`, com ou sem anotação de tipo; `let a, b = f();`.

Controle de fluxo:

- `if` / `else if` / `else` como expressão; `match` com bind de payload,
  várias variantes por braço, constantes, faixas (`1..50`) e `_`.
- `while`, `loop { }`, `for i in n`, `for i in a..b`, `for x in array`,
  `for &x in array` (com escrita de volta no array).
- `break`, `continue`, `block { }` com `break valor`, `guard c;`,
  `guard c else { … }` e `defer`.

Valores:

- Inteiros com largura (`u8 + 42` estoura em 8 bits e o literal adota a largura
  do outro operando), `f64`, `bool`, texto e `null`.
- `as` e `as!` para converter.
- `struct` com campos tipados e defaults, literais por nome ou posição,
  leitura e atribuição de campo, aritmética elemento a elemento.
- `enum` com variantes com e sem payload; `Shape.Circle { r: 1.0 }`,
  `Shape.Dot`.
- Arrays `i64[>..]`, `[7, 8, 9]`, slices `a[1..4]`, `a[^2..]`, `a[..]`,
  `.len`, `.cap`, `push`, `pop`, `append`.
- `print(...)`, `str(...)` e `format(array, …)`; `u8[>..]` é texto.

### O que ainda falta

`import` e a biblioteca padrão (`std`, `sort`, `json`, `regex`…), `enum` em
modo variável (`Shape..`), referências com dono (`T&`) e `format` de structs.
O interpretador avisa com mensagem clara quando encontra `import` ou `const`.

## GitHub no app

Menu **⋯ → GitHub**.

| ação | o que faz |
|---|---|
| Conectar ao GitHub | guarda o token no Keychain do iPhone e mostra a conta |
| Abrir do GitHub | lista repositórios, escolhe branch, lista os `.goose` e abre o arquivo no editor |
| Commitar | envia o texto atual com mensagem, para a branch e o caminho escolhidos |

Detalhes que valem saber:

- O token é um personal access token. Fine-grained precisa de **Contents: read
  and write** no repositório; clássico precisa do escopo `repo`.
- O app fala direto com `api.github.com`; não há clone nem `git` no aparelho.
- Ao abrir um arquivo, o app guarda o id do blob. No commit ele manda esse id
  junto, então se alguém alterou o arquivo no meio do caminho o GitHub recusa
  em vez de sobrescrever o trabalho de outra pessoa.
- Depois de commitar, o id novo vem na própria resposta e é guardado, sem
  requisição extra.
- Erros aparecem em português: token inválido, sem permissão, arquivo que mudou,
  caminho inexistente e limite de requisições com o horário de liberação.

O cabeçalho do editor mostra `repositório · caminho` enquanto um arquivo do
GitHub está aberto; escolher um exemplo limpa esse vínculo.

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

O cliente GitHub tem testes próprios que não tocam na rede: o transporte HTTP
é injetado, então cada chamada é conferida contra uma resposta fixa
(`swift test --filter GooseGitHubTests`).

`goosectl` (mesmo pacote) roda um arquivo solto:
`.build/debug/goosectl run programa.goose`.

## Executar o app

1. Abra `GooseIDE.xcodeproj` no Xcode em um Mac.
2. Selecione o scheme `GooseIDE` e um simulador de iPhone.
3. Execute com `Cmd+R`.

## Instalar no iPhone

### Com um Mac

O projeto já traz o bundle `com.beretdt.GooseIDE` e gera o `Info.plist`
automaticamente, então não falta nenhum arquivo de configuração. Falta apenas
escolher a sua equipe de assinatura:

1. Conecte o iPhone por cabo e confie no computador.
2. No Xcode, selecione o projeto `GooseIDE` → target `GooseIDE` →
   **Signing & Capabilities**.
3. Marque **Automatically manage signing** e escolha o seu Team (um Apple ID
   comum serve; o app fica válido por 7 dias e precisa ser reinstalado depois).
4. Se o bundle id já estiver em uso no seu time, troque
   `PRODUCT_BUNDLE_IDENTIFIER` para algo como `com.seudominio.GooseIDE`.
5. Em **Window → Devices and Simulators**, escolha o iPhone como destino e
   rode com `Cmd+R`.
6. Na primeira execução o iOS bloqueia o app até você liberar em
   **Ajustes → Geral → VPN e Gerenciamento de Dispositivos**.

### Sem um Mac

Um app iOS precisa de assinatura para rodar em aparelho, e isso o Xcode faz por
você. Sem Mac, o trabalho se divide: o CI compila, o seu computador assina e
instala.

**1. O CI produz um `.ipa` não assinado.** O workflow `Unsigned IPA` roda num
runner macOS do GitHub e publica o artefato — não precisa de conta Apple:

```sh
gh workflow run build-ipa.yml
gh run watch
gh run download --name GooseIDE-unsigned-ipa
```

Ou baixe pela aba **Actions** do repositório. O `.ipa` sai com hash SHA-256 ao
lado, para conferir o arquivo antes de instalar.

**2. Assine e instale com o seu Apple ID.** O aparelho precisa de iOS 17 ou
mais novo (arm64). Há duas opções:

*A — AltServer-Linux, tudo pelo Kali.*

```sh
sudo apt install usbmuxd libimobiledevice-utils
```

Baixe o `AltServer` de `NyaMisty/AltServer-Linux`, conecte o iPhone por cabo e
confie no computador, e rode o AltServer. Ele instala o **AltStore** no
aparelho usando o seu Apple ID. Depois mande o `GooseIDE-unsigned.ipa` para o
iPhone (AirDrop não existe no Linux; use o app Arquivos via nuvem, ou
`ifuse`, ou um link de download) e abra pelo AltStore.

*B — SideStore, sem depender de um processo rodando no PC.*
O AltServer instala o SideStore uma vez; depois ele se renova sozinho pelo
Wi-Fi usando um arquivo de emparelhamento gerado com `pymobiledevice3`.

Em ambos os casos, com Apple ID grátis valem as regras da Apple: **7 dias de
validade**, no máximo 3 apps assinados por conta, e o certificado precisa ser
renovado — o AltStore/SideStore faz isso automaticamente enquanto o aparelho
enxergar o computador na mesma rede.

*C — Alugar um Mac na nuvem.* MacinCloud e similares cobram por hora e já vêm
com Xcode; é o caminho mais próximo do "normal", e dispensa todo o processo de
sideloading.

O app funciona inteiramente no aparelho: nenhum código sai do telefone, e o
programa em edição é salvo localmente (o rascunho volta ao reabrir o app).

### O que observar no teste

- O editor mantém o cursor ao realçar; acima de 20 mil caracteres ele fica sem
  cor para não pesar.
- Aninhamento acima de 200 níveis, laços infinitos, recursão acima de 200
  chamadas e saída acima de 500 mil caracteres são recusados com mensagem, em
  vez de derrubar o app.
- A execução roda fora da thread principal, com o tempo em ms mostrado no
  painel de saída.

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
