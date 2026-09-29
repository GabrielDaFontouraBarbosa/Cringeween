# CRINGEWEEN · formulário de músicas

Página única onde a galera sugere músicas pra festa. A fila é pública e
atualiza ao vivo, sem precisar recarregar.

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
