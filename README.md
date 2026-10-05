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
2. Em **Authentication → Sign In / Providers**, desliga o cadastro público e cria
   o usuário do admin na mão (**Users → Add user**). As políticas liberam escrita
   pra qualquer usuário logado, então ninguém mais pode conseguir criar conta.
3. Abre `jogo.html#admin` → **ENTRAR** → escolhe o mp3 → **IMPORTAR JSON** com o
   chart da pasta [fases/](fases/) → **TESTAR** → **PUBLICAR**.

Charts prontos: [fases/misery-business.json](fases/misery-business.json)
(Paramore, 173 bpm, 578 notas sendo 26 longas, difícil).

### Nome, placar e moedas

- Na primeira vez o jogo pergunta o **nome** (até 12 letras, dá pra trocar clicando no
  nome no canto da tela). Ele aparece no **placar** de cada música, na seleção de fases.
- Pro placar funcionar, roda o [schema-placar.sql](schema-placar.sql) no SQL Editor do
  Supabase. Sem ele o jogo funciona normal, só não mostra placar. A pontuação só é enviada
  quando bate o recorde pessoal do aparelho, e o placar mostra a melhor de cada nome.
  Não tem como impedir 100% de fraude num jogo 100% no navegador; o admin pode apagar
  linhas suspeitas na tabela `placar`.
- Cada fase completa dá **moedas** (acertos + bônus da nota: S 15, A 8, B 4, C 2). Ficam
  guardadas no aparelho. O botão **LOJA** (skins da cringe-chan) ainda é "em breve".

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
