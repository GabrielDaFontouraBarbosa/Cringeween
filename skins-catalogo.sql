-- CRINGE HERO · catálogo de skins da cringe-chan
-- rode no Supabase → SQL Editor (depois do schema-contas.sql). Pode rodar de novo sem problema.
--
-- o "id" tem que ser igual à chave em SKINS no jogo.html (é o que vai pro perfis.skin_atual).
-- preço em moedas: uma fase rende ~20 a 60 moedas (acertos ÷ 10 + bônus da nota).

insert into public.skins (id, nome, preco) values
  ('miku',   'Hatsune Miku', 250),
  ('glitch', 'GL!TCH',       404)
on conflict (id) do nothing;   -- não sobrescreve preço/nome que o admin já tenha mudado

select id, nome, preco, ativa from public.skins order by preco;
