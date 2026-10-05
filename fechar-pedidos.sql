-- CRINGEWEEN · pedidos encerrados
-- rode no Supabase → SQL Editor → New query → Run
-- tira a permissão de inserir: a lista continua pública pra ler, mas ninguém adiciona mais nada

drop policy if exists "todo mundo sugere" on public.sugestoes;

-- pra reabrir os pedidos um dia:
-- create policy "todo mundo sugere" on public.sugestoes for insert to anon, authenticated with check (true);
-- (authenticated junto porque quem jogou o Cringe Hero tem conta de jogador no mesmo navegador)
