-- CRINGE HERO · rode no Supabase → SQL Editor (depois do schema.sql)

create table public.fases (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  title       text not null check (char_length(title) between 1 and 80),
  artist      text check (char_length(artist) <= 80),
  difficulty  text,
  bpm         numeric not null check (bpm between 40 and 400),
  offset_ms   integer not null default 0,
  notes       jsonb not null default '[]'::jsonb,   -- [{ "b": tempo_em_beats, "l": pista 0-3 }]
  audio_path  text not null,
  published   boolean not null default true
);

alter table public.fases enable row level security;

-- qualquer um vê as fases publicadas
create policy "fases publicadas sao publicas"
  on public.fases for select to anon using (published);

-- só o admin logado cria / edita / apaga (e vê rascunhos)
create policy "admin le tudo"     on public.fases for select to authenticated using (true);
create policy "admin cria"        on public.fases for insert to authenticated with check (true);
create policy "admin edita"       on public.fases for update to authenticated using (true) with check (true);
create policy "admin apaga"       on public.fases for delete to authenticated using (true);

-- bucket público pras músicas (qualquer um ouve, só o admin sobe)
insert into storage.buckets (id, name, public) values ('musicas', 'musicas', true)
  on conflict (id) do nothing;

create policy "admin sobe musica"   on storage.objects for insert to authenticated with check (bucket_id = 'musicas');
create policy "admin troca musica"  on storage.objects for update to authenticated using (bucket_id = 'musicas');
create policy "admin apaga musica"  on storage.objects for delete to authenticated using (bucket_id = 'musicas');
