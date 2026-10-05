-- CRINGE HERO · placar por música · rode no Supabase → SQL Editor (depois do schema-jogo.sql)

create table public.placar (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  fase_key    text    not null check (char_length(fase_key) between 1 and 60),   -- "demo" ou "db:<id da fase>"
  player      text    not null check (char_length(player) between 1 and 12),
  score       integer not null check (score between 0 and 10000000),
  grade       text    check (grade in ('S','A','B','C','D')),
  acc         numeric check (acc between 0 and 100)
);

create index placar_fase_score on public.placar (fase_key, score desc);

alter table public.placar enable row level security;

-- qualquer um vê o placar e manda a própria pontuação (só inserir: ninguém edita nem apaga as dos outros)
create policy "placar publico"       on public.placar for select to anon, authenticated using (true);
create policy "placar aceita score"  on public.placar for insert to anon, authenticated with check (true);

-- só o admin logado limpa o placar (ex.: tirar nome feio ou pontuação fajuta)
create policy "admin limpa placar"   on public.placar for delete to authenticated using (true);
