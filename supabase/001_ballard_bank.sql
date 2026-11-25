
-- BALLARD BANK MULTIPLAYER: execute UMA vez no SQL Editor.
-- Saldos são créditos fictícios do jogo.
create table if not exists public.game_wallets (
  user_id uuid primary key references auth.users(id) on delete cascade,
  balance numeric(18,2) not null default 0 check (balance >= 0),
  updated_at timestamptz not null default now()
);
create table if not exists public.balance_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  amount numeric(18,2) not null check (amount > 0 and amount <= 1000000000000),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id)
);
create table if not exists public.game_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  amount numeric(18,2) not null,
  entry_type text not null check (entry_type = 'master_credit'),
  description text not null,
  created_at timestamptz not null default now()
);
alter table public.game_wallets enable row level security;
alter table public.balance_requests enable row level security;
alter table public.game_ledger enable row level security;
drop policy if exists wallet_read_own on public.game_wallets;
create policy wallet_read_own on public.game_wallets for select to authenticated using (auth.uid() = user_id);
drop policy if exists requests_read_own on public.balance_requests;
create policy requests_read_own on public.balance_requests for select to authenticated using (auth.uid() = user_id);
drop policy if exists ledger_read_own on public.game_ledger;
create policy ledger_read_own on public.game_ledger for select to authenticated using (auth.uid() = user_id);

create or replace function public.create_ballard_wallet()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
 insert into public.game_wallets(user_id,balance) values(new.id,0)
 on conflict(user_id) do nothing;
 return new;
end; $$;
drop trigger if exists on_profile_created_wallet on public.profiles;
create trigger on_profile_created_wallet after insert on public.profiles
for each row execute procedure public.create_ballard_wallet();
insert into public.game_wallets(user_id,balance)
select id,0 from public.profiles on conflict(user_id) do nothing;

create or replace function public.request_game_balance(p_amount numeric)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid; v_status text;
begin
 select account_status into v_status from public.profiles where id=auth.uid();
 if v_status is distinct from 'approved' then raise exception 'Conta ainda não aprovada.'; end if;
 if p_amount is null or p_amount <= 0 or p_amount > 1000000000000 then raise exception 'Valor inválido.'; end if;
 insert into public.balance_requests(user_id,amount) values(auth.uid(),p_amount) returning id into v_id;
 return v_id;
end; $$;

create or replace function public.master_list_balance_requests()
returns table(id uuid,user_id uuid,amount numeric,created_at timestamptz,full_name text)
language plpgsql security definer set search_path = ''
as $$
begin
 if not exists(select 1 from public.profiles where profiles.id=auth.uid()
   and profiles.role='master' and profiles.account_status='approved') then
   raise exception 'Acesso negado: somente MASTER aprovado.';
 end if;
 return query select br.id,br.user_id,br.amount,br.created_at,p.full_name
 from public.balance_requests br left join public.profiles p on p.id=br.user_id
 where br.status='pending' order by br.created_at asc;
end; $$;

create or replace function public.master_review_balance_request(p_request_id uuid,p_decision text)
returns text language plpgsql security definer set search_path = ''
as $$
declare v_req public.balance_requests%rowtype;
begin
 if not exists(select 1 from public.profiles where profiles.id=auth.uid()
   and profiles.role='master' and profiles.account_status='approved') then
   raise exception 'Acesso negado: somente MASTER aprovado.';
 end if;
 if p_decision not in ('approved','rejected') then raise exception 'Decisão inválida.'; end if;
 select * into v_req from public.balance_requests
 where id=p_request_id and status='pending' for update;
 if not found then raise exception 'Pedido inexistente ou já analisado.'; end if;
 update public.balance_requests set status=p_decision,reviewed_at=now(),reviewed_by=auth.uid()
 where id=p_request_id;
 if p_decision='approved' then
   insert into public.game_wallets(user_id,balance) values(v_req.user_id,v_req.amount)
   on conflict(user_id) do update set balance=public.game_wallets.balance+excluded.balance,updated_at=now();
   insert into public.game_ledger(user_id,amount,entry_type,description)
   values(v_req.user_id,v_req.amount,'master_credit','Crédito virtual aprovado pelo MASTER');
 end if;
 return p_decision;
end; $$;

revoke all on function public.request_game_balance(numeric) from public,anon;
revoke all on function public.master_list_balance_requests() from public,anon;
revoke all on function public.master_review_balance_request(uuid,text) from public,anon;
grant execute on function public.request_game_balance(numeric) to authenticated;
grant execute on function public.master_list_balance_requests() to authenticated;
grant execute on function public.master_review_balance_request(uuid,text) to authenticated;
