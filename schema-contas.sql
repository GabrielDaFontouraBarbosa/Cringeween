-- CRINGE HERO · contas dos jogadores + revisão de segurança
-- rode UMA vez no Supabase → SQL Editor (depois do schema-jogo.sql e do schema-placar.sql)
--
-- ANTES DE RODAR:
--   1. Authentication → Sign In / Providers → liga "Allow anonymous sign-ins"
--      (cada aparelho vira uma conta sem e-mail; o nome e as moedas ficam no banco)
--   2. troca SEU-EMAIL-AQUI (seção 1) pelo e-mail do usuário admin
--
-- POR QUE: com login anônimo, todo jogador vira "authenticated" — e as policies antigas
-- liberavam escrita nas fases e nas músicas pra qualquer "authenticated". Agora só quem
-- está na tabela admins escreve. Moedas e placar só mudam pelas funções daqui, que
-- conferem a partida no servidor.

-- =====================================================================
-- 1) ADMINS
-- =====================================================================
create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table public.admins enable row level security;   -- sem policy: ninguém lê nem escreve pela API

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where user_id = auth.uid())
     and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false;
$$;

insert into public.admins (user_id)
  select id from auth.users where lower(email) = lower('SEU-EMAIL-AQUI')
  on conflict do nothing;

-- =====================================================================
-- 2) FASES E MÚSICAS: escrita só pro admin
-- =====================================================================
drop policy if exists "fases publicadas sao publicas" on public.fases;
drop policy if exists "admin le tudo" on public.fases;
drop policy if exists "admin cria"    on public.fases;
drop policy if exists "admin edita"   on public.fases;
drop policy if exists "admin apaga"   on public.fases;

create policy "fases publicadas sao publicas" on public.fases for select to anon, authenticated
  using (published or public.is_admin());
create policy "admin cria"  on public.fases for insert to authenticated with check (public.is_admin());
create policy "admin edita" on public.fases for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admin apaga" on public.fases for delete to authenticated using (public.is_admin());

drop policy if exists "admin sobe musica"  on storage.objects;
drop policy if exists "admin troca musica" on storage.objects;
drop policy if exists "admin apaga musica" on storage.objects;

create policy "admin sobe musica"  on storage.objects for insert to authenticated
  with check (bucket_id = 'musicas' and public.is_admin());
create policy "admin troca musica" on storage.objects for update to authenticated
  using (bucket_id = 'musicas' and public.is_admin());
create policy "admin apaga musica" on storage.objects for delete to authenticated
  using (bucket_id = 'musicas' and public.is_admin());

-- a fila de sugestões do site é lida por quem tem conta de jogador também
-- (o site e o jogo dividem a sessão, então sem isso a fila sumiria pra quem jogou)
drop policy if exists "todo mundo ve a fila" on public.sugestoes;
create policy "todo mundo ve a fila" on public.sugestoes for select to anon, authenticated using (true);

-- =====================================================================
-- 3) PERFIS DOS JOGADORES (nome, moedas, skins)
-- =====================================================================
create table if not exists public.perfis (
  id             uuid primary key references auth.users(id) on delete cascade,
  created_at     timestamptz not null default now(),
  nome           text not null check (char_length(nome) between 1 and 12),
  moedas         integer not null default 0 check (moedas >= 0),
  skins          text[] not null default '{}',
  skin_atual     text,
  ultima_partida timestamptz
);
create unique index if not exists perfis_nome_unico on public.perfis (lower(nome));   -- ninguém se passa por outro no placar
alter table public.perfis enable row level security;

drop policy if exists "jogador ve o proprio perfil" on public.perfis;
create policy "jogador ve o proprio perfil" on public.perfis for select to authenticated using (id = auth.uid());
-- sem insert/update/delete pela API: tudo passa pelas funções abaixo

-- catálogo de skins (a loja ainda é "em breve"; o admin cadastra aqui depois)
create table if not exists public.skins (
  id    text primary key check (char_length(id) between 1 and 40),
  nome  text not null,
  preco integer not null check (preco >= 0),
  ativa boolean not null default true
);
alter table public.skins enable row level security;
drop policy if exists "catalogo publico" on public.skins;
drop policy if exists "admin mexe no catalogo" on public.skins;
create policy "catalogo publico" on public.skins for select to anon, authenticated using (ativa or public.is_admin());
create policy "admin mexe no catalogo" on public.skins for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- =====================================================================
-- 4) PLACAR: agora só entra pelo registrar_partida (nada de insert direto)
-- =====================================================================
alter table public.placar add column if not exists user_id uuid references auth.users(id) on delete cascade;
create unique index if not exists placar_um_por_jogador on public.placar (fase_key, user_id);

drop policy if exists "placar aceita score" on public.placar;
drop policy if exists "placar publico"      on public.placar;
drop policy if exists "admin limpa placar"  on public.placar;
create policy "placar publico"     on public.placar for select to anon, authenticated using (true);
create policy "admin limpa placar" on public.placar for delete to authenticated using (public.is_admin());

-- =====================================================================
-- 5) FUNÇÕES (rodam no servidor; o navegador só chama)
-- =====================================================================

-- cria/troca o nome do jogador
create or replace function public.definir_nome(p_nome text) returns public.perfis
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n text; r public.perfis;
begin
  if uid is null then raise exception 'sem sessão'; end if;
  n := btrim(regexp_replace(coalesce(p_nome, ''), '\s+', ' ', 'g'));
  if char_length(n) < 1 or char_length(n) > 12 or n ~ '[<>[:cntrl:]]' then
    raise exception 'nome inválido (1 a 12 letras)';
  end if;
  begin
    insert into perfis (id, nome) values (uid, n)
      on conflict (id) do update set nome = excluded.nome
      returning * into r;
  exception when unique_violation then
    raise exception 'esse nome já tem dono 💀';
  end;
  update placar set player = n where user_id = uid;
  return r;
end $$;

-- fim de fase: confere a partida contra o chart, dá as moedas e atualiza o placar
create or replace function public.registrar_partida(
  p_fase text, p_score integer, p_perfect integer, p_good integer, p_ok integer, p_miss integer
) returns json
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); me public.perfis; f public.fases;
  total int; holds int; sum_d numeric; dur numeric;
  acc numeric; nota text; ganho int; pos int;
begin
  if uid is null then raise exception 'sem sessão'; end if;
  select * into me from perfis where id = uid for update;
  if not found then raise exception 'escolhe um nome primeiro'; end if;

  -- tamanho da fase (o tutorial é gerado no navegador: números fixos)
  if p_fase = 'demo' then
    total := 78; holds := 6; sum_d := 12; dur := 35;
  elsif p_fase like 'db:%' then
    select * into f from fases where id::text = substr(p_fase, 4) and published;
    if not found then raise exception 'fase não existe'; end if;
    select count(*),
           count(*) filter (where coalesce((e.n ->> 'd')::numeric, 0) >= 0.5),
           coalesce(sum((e.n ->> 'd')::numeric) filter (where coalesce((e.n ->> 'd')::numeric, 0) >= 0.5), 0),
           coalesce(max((e.n ->> 'b')::numeric + coalesce((e.n ->> 'd')::numeric, 0)), 0)
      into total, holds, sum_d, dur
      from jsonb_array_elements(f.notes) as e(n);
    dur := f.offset_ms / 1000.0 + dur * 60 / f.bpm;
  else
    raise exception 'fase inválida';
  end if;

  -- a partida tem que fazer sentido com o chart
  if least(p_perfect, p_good, p_ok, p_miss) < 0 or p_perfect + p_good + p_ok + p_miss <> total then
    raise exception 'contagem não bate com a fase';
  end if;
  if p_score < 0 or p_score > (p_perfect * 300 + p_good * 150 + p_ok * 50) * 4 + (sum_d + holds) * 240 then
    raise exception 'pontuação impossível';
  end if;
  -- não dá pra terminar duas músicas mais rápido do que elas tocam
  if me.ultima_partida is not null and now() - me.ultima_partida < make_interval(secs => dur * 0.8) then
    raise exception 'calma, termina a música primeiro';
  end if;

  -- nota e moedas calculadas aqui (mesma regra do jogo)
  acc := case when total > 0 then (p_perfect + p_good * 0.66 + p_ok * 0.33) / total * 100 else 0 end;
  nota := case when p_miss = 0 and acc >= 95 then 'S' when acc >= 90 then 'A' when acc >= 80 then 'B'
               when acc >= 65 then 'C' else 'D' end;
  ganho := floor((p_perfect + p_good * 0.6 + p_ok * 0.2) / 10)::int
         + case nota when 'S' then 15 when 'A' then 8 when 'B' then 4 when 'C' then 2 else 0 end;

  update perfis set moedas = moedas + ganho, ultima_partida = now() where id = uid returning * into me;

  insert into placar (fase_key, user_id, player, score, grade, acc)
    values (p_fase, uid, me.nome, p_score, nota, round(acc, 1))
    on conflict (fase_key, user_id) do update
      set score = excluded.score, grade = excluded.grade, acc = excluded.acc,
          player = excluded.player, created_at = now()
      where placar.score < excluded.score;

  select 1 + count(*) into pos from placar
    where fase_key = p_fase
      and score > (select score from placar where fase_key = p_fase and user_id = uid);

  return json_build_object('moedas_ganhas', ganho, 'moedas', me.moedas, 'nota', nota, 'posicao', pos);
end $$;

-- loja (pronta pro dia que tiver skins)
create or replace function public.comprar_skin(p_skin text) returns public.perfis
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s public.skins; r public.perfis;
begin
  if uid is null then raise exception 'sem sessão'; end if;
  select * into s from skins where id = p_skin and ativa;
  if not found then raise exception 'skin não existe'; end if;
  select * into r from perfis where id = uid for update;
  if not found then raise exception 'escolhe um nome primeiro'; end if;
  if p_skin = any (r.skins) then raise exception 'você já tem essa skin'; end if;
  if r.moedas < s.preco then raise exception 'moedas insuficientes'; end if;
  update perfis set moedas = moedas - s.preco, skins = array_append(skins, p_skin)
    where id = uid returning * into r;
  return r;
end $$;

create or replace function public.usar_skin(p_skin text) returns public.perfis
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r public.perfis;
begin
  if uid is null then raise exception 'sem sessão'; end if;
  select * into r from perfis where id = uid for update;
  if not found then raise exception 'escolhe um nome primeiro'; end if;
  if p_skin is not null and not (p_skin = any (r.skins)) then raise exception 'você não tem essa skin'; end if;
  update perfis set skin_atual = p_skin where id = uid returning * into r;
  return r;
end $$;

-- só jogador com sessão chama as funções
revoke execute on function public.definir_nome(text) from public, anon;
revoke execute on function public.registrar_partida(text, integer, integer, integer, integer, integer) from public, anon;
revoke execute on function public.comprar_skin(text) from public, anon;
revoke execute on function public.usar_skin(text) from public, anon;
grant execute on function public.definir_nome(text) to authenticated;
grant execute on function public.registrar_partida(text, integer, integer, integer, integer, integer) to authenticated;
grant execute on function public.comprar_skin(text) to authenticated;
grant execute on function public.usar_skin(text) to authenticated;

-- confere: tem que aparecer 1 linha (o seu usuário). Se vier vazio, o e-mail da seção 1 tá errado.
select u.email from public.admins a join auth.users u on u.id = a.user_id;
