# BALLARD BANK MULTIPLAYER
Starter Flutter + Supabase para um jogo multiplayer de banco virtual.

## Incluído
- Cadastro/login por e-mail.
- Jogador só entra após aprovação no perfil `profiles`.
- Carteira individual com saldo inicial zero.
- Solicitação de créditos fictícios.
- MASTER aprovado lista pedidos e aprova/recusa.
- Saldo só é alterado no servidor após aprovação MASTER.
- Políticas RLS e funções SQL protegidas.

## Configuração
1. No Supabase, abra SQL Editor e execute uma vez `supabase/001_ballard_bank.sql`.
2. Em um computador com Flutter instalado, descompacte e execute:

```bash
flutter pub get
flutter run --dart-define=SUPABASE_URL=SUA_URL --dart-define=SUPABASE_ANON_KEY=SUA_CHAVE_ANON_PUBLICA
```

A URL e a chave anon/public ficam em Project Settings > API. Nunca use `service_role` no aplicativo.

A conta MASTER existente precisa estar em `profiles` com `role='master'` e `account_status='approved'`.

Este é código-fonte inicial, não APK/IPA pronto; não foi compilado nesta sessão. Todos os saldos são fictícios. Não há PIX, pagamentos nem dinheiro real.
