# Goose IDE

Um editor para escrever e rodar Goose no iPhone, com interpretador local. A
execução do programa é local. Se você usar o agente de IA, o prompt, o histórico
da conversa e o programa atual são enviados ao provedor configurado.

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
- **82 testes** (46 do interpretador, 15 do cliente GitHub, 21 do cliente de IA)
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

O target declara iOS 16 como versão mínima.

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

O projeto tem um target iOS com versão mínima 16. O workflow `Unsigned IPA`
compila o app sem assinar em um runner macOS e publica o `.ipa`; não é
necessário ter um Mac ou uma conta Apple para gerar o artefato.

> **Limitação conhecida (2026-11-08):** gerar e validar o IPA no CI não garante
> a instalação no aparelho. O AltServer-Linux testado aqui falha na autenticação
> Apple com `-80045`, inclusive com Anisette v3 local e o fork Linux mais recente
> testado. A instalação inicial pelo Kali ainda não está resolvida; acompanhe o
> [issue #3](https://github.com/beretdt/goose-ide/issues/3). Para testar no
> iPhone agora, use um Mac ou PC Windows com um fluxo de assinatura compatível.

**1. Baixe o artefato.** O workflow roda manualmente, em pull requests e em
tags `v*`. Dispare-o pela aba **Actions** ou use:

```sh
gh workflow run build-ipa.yml
gh run watch
gh run download --name GooseIDE-unsigned-ipa
```

O artefato `GooseIDE-unsigned-ipa` contém `GooseIDE-unsigned.ipa` e o hash
SHA-256. O workflow também verifica a estrutura `Payload/GooseIDE.app`, o
`Info.plist`, o bundle ID, a plataforma iPhoneOS e a arquitetura arm64. Essas
verificações detectam erros de empacotamento, mas não substituem o teste de
instalação em um iPhone.

**2. Instale e renove pelo SideStore.** Siga a
[documentação oficial do SideStore](https://docs.sidestore.io/) para fazer a
configuração inicial, incluindo instalar o SideStore e parear o aparelho.
Depois, importe o `.ipa` no SideStore e use a ação de atualização antes de a
assinatura expirar. Com uma conta Apple gratuita, apps assinados por sideload
expiram em 7 dias e há um limite de 3 apps ativos; confira que a atualização
terminou com sucesso.

Após a configuração inicial, o SideStore pode renovar sem o AltServer rodando
no computador. A renovação pode ser tentada por dados móveis, desde que o
SideStore, o StosVPN e a rede consigam alcançar os serviços necessários.
Captive portals, filtros de DNS/VPN ou outras restrições podem impedir a
renovação; faça-a antes do vencimento e prefira uma conexão confiável.

O AltStore é uma alternativa, mas depende do AltServer ligado e alcançável
pela rede local durante a renovação. Um túnel Tailscale até um AltServer
remoto não garante a descoberta local que esse fluxo espera. O Sideloadly
também pode assinar o IPA em um PC Windows, mas a assinatura gratuita continua
expirando em 7 dias.

O projeto atualmente tem um único target de app iOS e não declara arquivos
`.entitlements` nem extensões. Ao adicionar capabilities ou extensões, confira
os requisitos de assinatura de cada entitlement e bundle: a conta gratuita
não oferece todas as capabilities. A presença de uma string
`com.apple.developer.*`, por si só, não determina se a assinatura gratuita é
compatível. O workflow também força `CODE_SIGNING_ENTITLEMENTS=""`; revise
essa configuração e teste o processo de assinatura ao introduzir capabilities.

Sem usar os recursos de rede, a execução e o rascunho ficam no aparelho. O
recurso GitHub acessa a API do GitHub; ao enviar uma mensagem ao agente de IA,
o programa atual e a conversa são enviados ao provedor selecionado.

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
