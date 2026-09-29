-- CRINGEWEEN · rode isto no Supabase → SQL Editor → New query → Run

create table public.sugestoes (
  id         uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  name       text not null check (char_length(name)   between 1 and 80),
  song       text not null check (char_length(song)   between 1 and 80),
  artist     text          check (char_length(artist) <= 80),
  genre      text          check (char_length(genre)  <= 80),
  song_key   text not null check (char_length(song_key) between 1 and 100)
);

-- impede a mesma música duas vezes (comparação sem acento/maiúscula feita no site)
create unique index sugestoes_song_key_idx on public.sugestoes (song_key);

-- segurança: qualquer um pode ver e adicionar; ninguém edita nem apaga (só você pelo painel)
alter table public.sugestoes enable row level security;

create policy "todo mundo ve a fila"
  on public.sugestoes for select to anon using (true);

create policy "todo mundo sugere"
  on public.sugestoes for insert to anon with check (true);

-- liga o tempo real pra fila atualizar sozinha
alter publication supabase_realtime add table public.sugestoes;
