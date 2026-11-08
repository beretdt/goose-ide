# Runner C e Assembly

Goose continua sendo interpretado no iPhone. Arquivos `.c` e `.asm` usam um servidor Piston que você controla: C roda com GCC e Assembly usa NASM x86-64 no Linux do servidor, não no processador ARM64 do iPhone.

O endpoint público do Piston exige autorização, então este projeto usa uma instância própria na rede local.

## Subir o servidor

```sh
./runner/start-piston.sh                # descobre o IP da rota padrão
./runner/start-piston.sh 192.168.15.5   # ou informe o IP da Wi-Fi
```

O script clona o Piston em `~/piston` se necessário, cria o container `piston_api`, instala os runtimes e imprime o endereço para colar no app.

Ele existe por um motivo específico: o entrypoint oficial liga os controladores cgroup `cpuset` e `io`, que não existem no namespace de um Podman rootless. O script monta um entrypoint que habilita apenas os controladores disponíveis e mantém o resto do sandbox do Piston. Sem isso o container sai com `write error: No such file or directory` ao escrever em `cgroup.subtree_control`.

Detalhes que o script resolve:

- `--cgroupns=private` é obrigatório para poder criar cgroups em rootless.
- A porta fica presa ao IP informado (`-p 192.168.15.5:2000:2000`), não em todas as interfaces.
- O pacote que fornece a linguagem `c` chama-se `gcc`; o pacote `nasm` fornece `nasm`, `nasm32`, `nasm64` e `asm64`.

## Verificar

```sh
curl -s http://192.168.15.5:2000/api/v2/runtimes
```

Deve listar `c` (runtime `gcc`) e `nasm64` (runtime `nasm`).

Teste rápido de execução:

```sh
curl -s -X POST http://192.168.15.5:2000/api/v2/execute \
  -H 'Content-Type: application/json' \
  -d '{"language":"c","version":"*","files":[{"name":"main.c","content":"#include <stdio.h>\nint main(void){puts(\"ok\");return 0;}\n"}]}'
```

## Conectar o iPhone

1. Deixe o iPhone e o Kali na mesma rede Wi-Fi confiável.
2. Descubra o endereço local com `ip -4 -o addr show dev wlan0`.
3. No Goose IDE, abra `+` → `Execução` → `Configurar runner C/Assembly` e informe `http://<IP>:2000`.
4. Ao executar C ou NASM pela primeira vez, confirme o envio e permita o acesso à rede local no iPhone.

O app limita compilação a 10 segundos e execução a 3 segundos. O código é enviado somente ao endpoint configurado; Goose nunca sai do aparelho.

## Segurança

Piston é um executor de código arbitrário. Mantenha a porta 2000 restrita à rede privada, nunca publique na internet e não use em Wi-Fi pública ou compartilhada.

O container usa `--restart=always`, mas em Podman rootless ele só volta no boot se o usuário tiver lingering ativo:

```sh
loginctl enable-linger "$USER"
```
