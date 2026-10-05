# CRINGEWEEN · formulário de músicas

Página única onde a galera sugeria músicas pra festa. **Os pedidos estão
encerrados**: a página agora agradece, mostra as últimas que entraram e tem o
botão **VER TODAS AS MÚSICAS** com a lista completa (com busca).

Pra fechar também no banco (ninguém consegue inserir nem pela API), roda o
[fechar-pedidos.sql](fechar-pedidos.sql) no SQL Editor do Supabase.

**Festa:** domingo, 18/10/2026 · 16h–22h · Rua dos Geólogos, 185 — Taquara

## Como funciona

- Uma página só, sem build: HTML, CSS e JS num arquivo.
- Os dados ficam no [Supabase](https://supabase.com) (Postgres). O navegador
  fala direto com ele — não tem servidor próprio no meio.
- Cada pessoa pode mandar **2 músicas**. O limite é guardado no `localStorage`
  do navegador dela.
- Música repetida é bloqueada duas vezes: na hora de digitar (comparando sem
  acento nem maiúscula) e no banco, por índice único.
- A fila aparece em tempo real via Supabase Realtime.

## Pôr no ar

### 1. Criar o banco

No Supabase: **New project** → **SQL Editor** → **New query** → cola o
conteúdo de [schema.sql](schema.sql) → **Run**.

Isso cria a tabela `sugestoes`, o índice que impede repetição, as políticas de
acesso e liga o tempo real.

### 2. Preencher as duas chaves

Em **Settings → API** copia a *Project URL* e a *anon public key*. Cola nas
linhas 322–323 do [index.html](index.html):

```js
var SUPABASE_URL = "https://SEU-PROJETO.supabase.co";
var SUPABASE_ANON_KEY = "SUA-ANON-KEY";
```

Sem isso a fila não carrega e o formulário não envia.

### 3. Publicar

**Settings → Pages → Source: `main` / `/ (root)`**. Em alguns minutos o site
fica em `https://gabrieldafontourabarbosa.github.io/Cringeween/`.

## Cringe Hero (jogo de ritmo)

[jogo.html](jogo.html) é um "guitar hero" da festa: menu, seleção de fases, a
mascote cringe-chan em 3D e um modo admin (`jogo.html#admin`) pra montar fases.
O botão **JOGAR CRINGE HERO** no topo do [index.html](index.html) leva até ele.

Sem configurar nada, já dá pra jogar a fase **tutorial** (a música é gerada no
navegador). Pras fases de verdade:

1. No Supabase, roda o [schema-jogo.sql](schema-jogo.sql) no SQL Editor. Ele cria a
   tabela `fases` e o bucket público `musicas`.
2. Em **Authentication → Sign In / Providers**, desliga o cadastro público por e-mail
   e cria o usuário do admin na mão (**Users → Add user**, marcando *Auto Confirm User*).
3. Roda o [schema-placar.sql](schema-placar.sql) e depois o
   [schema-contas.sql](schema-contas.sql) (lê o topo dele antes: precisa ligar o login
   anônimo e trocar o e-mail do admin).
4. Abre `jogo.html#admin` → **ENTRAR** → escolhe o mp3 → **IMPORTAR JSON** com o
   chart da pasta [fases/](fases/) → **TESTAR** → **PUBLICAR**.

Charts prontos na pasta [fases/](fases/): Misery Business (difícil), Die In a Fire,
In the End, Scary Monsters And Nice Sprites e Alone (médio).

### Contas, placar e moedas

- Cada aparelho vira uma **conta anônima** no Supabase (sem e-mail nem senha). Na
  primeira vez o jogo pergunta o **nome** (até 12 letras, único — ninguém se passa por
  outro). Dá pra trocar clicando no nome no canto da tela.
- **Moedas** e **placar** ficam no banco, na tabela `perfis` e `placar`. O navegador
  nunca escreve direto nelas: no fim da fase ele chama a função `registrar_partida`,
  que confere a partida contra o chart (número de notas, pontuação máxima possível,
  tempo mínimo entre partidas), calcula a nota e as moedas e atualiza o placar.
- Moedas por fase: acertos ÷ 10 + bônus da nota (S 15, A 8, B 4, C 2).
- A **LOJA** ainda é "em breve", mas o banco já tem o catálogo `skins` e as funções
  `comprar_skin` / `usar_skin`.
- Limite: a conta anônima é do navegador. Limpou os dados do site ou trocou de aparelho,
  vira outro jogador. E num jogo que roda no navegador sempre dá pra forjar uma partida
  *plausível*; o servidor só barra as impossíveis. O admin pode apagar linhas da `placar`.

### Segurança (quem pode o quê)

| Tabela / função | Qualquer um | Jogador (anônimo) | Admin |
|---|---|---|---|
| `sugestoes` | ler (inserir enquanto os pedidos estão abertos) | ler | painel |
| `fases`, bucket `musicas` | ler as publicadas | ler as publicadas | tudo |
| `placar` | ler | só via `registrar_partida` | apagar |
| `perfis` | — | ler o próprio; mudar só via funções | painel |
| `skins` | ler | comprar via `comprar_skin` | tudo |

"Admin" = usuário que está na tabela `admins` **e** entrou com e-mail. Antes desta
mudança, qualquer usuário logado podia mexer nas fases; com o login anônimo isso
viraria qualquer visitante, por isso as policies foram trocadas pelo `is_admin()`.

### Notas longas e controle

- Nota com `"d"` no chart (duração em tempos) é **nota longa**: segura até o
  rastro acabar. No editor: clica e **arrasta pro lado**; gravando, é só segurar a tecla.
- Controle (Xbox/PlayStation/genérico): pistas = LT/←, LB/↑, RB/Y, RT/B.
  Nos menus ↑↓ escolhe, A confirma, B volta, START pausa.

### Gerar fase nova de um mp3

Precisa do [ffmpeg](https://ffmpeg.org) e do Node.

```
node tools/gerar-fase.js "Artista - Música.mp3" difícil
```

Detecta o BPM, alinha o tempo e escreve `fases/<musica>.json` (dificuldade:
`fácil`, `médio`, `difícil` ou `insano`). Depois é só importar no admin.

## Sobre a chave ficar exposta

A `anon key` vai pro código e **qualquer um consegue ler** — isso é normal no
Supabase, ela é feita pra isso. O que protege o banco não é esconder a chave,
é o Row Level Security do [schema.sql](schema.sql):

| Operação | Quem pode |
|---|---|
| Ver a fila (`select`) | qualquer um |
| Sugerir (`insert`) | qualquer um |
| Editar (`update`) | ninguém |
| Apagar (`delete`) | ninguém |

Ou seja: dá pra ler e adicionar, mas não dá pra mexer nem destruir o que já
está lá. Pra apagar alguma sugestão, use o painel do Supabase.

**Nunca** coloque aqui a `service_role key` — essa ignora o RLS e daria acesso
total ao banco pra quem lesse o código.
