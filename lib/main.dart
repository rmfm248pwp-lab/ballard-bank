
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const red = Color(0xFFD71936);
const dark = Color(0xFF252525);
late final SupabaseClient db;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (url.isEmpty || key.isEmpty) {
    runApp(const MaterialApp(home: Scaffold(body: Center(child: Text(
      'BALLARD BANK\nConfigure SUPABASE_URL e SUPABASE_ANON_KEY para iniciar.',
      textAlign: TextAlign.center)))));
    return;
  }
  await Supabase.initialize(url: url, anonKey: key);
  db = Supabase.instance.client;
  runApp(const BallardApp());
}

class BallardApp extends StatelessWidget {
  const BallardApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'BALLARD BANK', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: red),
      scaffoldBackgroundColor: const Color(0xFFF6F6F6)),
    home: const Gate());
}

class Gate extends StatelessWidget {
  const Gate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
    stream: db.auth.onAuthStateChange,
    builder: (_, __) => db.auth.currentUser == null ? const LoginPage() : const BankPage());
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}
class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController(), pass = TextEditingController(), name = TextEditingController();
  bool signup = false, busy = false;
  String note = '';
  Future<void> go() async {
    setState(() { busy = true; note = ''; });
    try {
      if (signup) {
        await db.auth.signUp(email: email.text.trim(), password: pass.text,
          data: {'full_name': name.text.trim()});
        note = 'Cadastro enviado. Confirme seu e-mail e aguarde aprovação MASTER.';
      } else {
        await db.auth.signInWithPassword(email: email.text.trim(), password: pass.text);
      }
    } on AuthException catch (e) { note = e.message; }
      catch (e) { note = 'Falha ao conectar: $e'; }
    if (mounted) setState(() => busy = false);
  }
  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Center(child:
    SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(height: 76, width: 76, alignment: Alignment.center,
          decoration: BoxDecoration(color: red, borderRadius: BorderRadius.circular(20)),
          child: const Text('B', style: TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w900))),
        const SizedBox(height: 18),
        const Text('BALLARD BANK', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: dark)),
        const Text('JOGO MULTIPLAYER • BANCO VIRTUAL', style: TextStyle(color: red, fontWeight: FontWeight.bold)),
        const SizedBox(height: 28),
        Text(signup ? 'Criar conta de jogador' : 'Entrar no jogo', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        if (signup) ...[const SizedBox(height: 12), TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome do jogador'))],
        const SizedBox(height: 12),
        TextField(controller: email, decoration: const InputDecoration(labelText: 'E-mail')),
        const SizedBox(height: 12),
        TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Senha')),
        const SizedBox(height: 16),
        FilledButton(onPressed: busy ? null : go, style: FilledButton.styleFrom(backgroundColor: red, padding: const EdgeInsets.all(16)),
          child: Text(busy ? 'Aguarde...' : signup ? 'CRIAR CONTA' : 'ENTRAR')),
        TextButton(onPressed: () => setState(() { signup = !signup; note = ''; }),
          child: Text(signup ? 'Já tenho conta — entrar' : 'Novo jogador? Criar conta')),
        if (note.isNotEmpty) Text(note, textAlign: TextAlign.center, style: const TextStyle(color: red)),
        const SizedBox(height: 20),
        const Text('Todos os saldos são fictícios e só existem dentro do jogo.', textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.black54)),
      ]))))));
}

class BankPage extends StatefulWidget {
  const BankPage({super.key});
  @override
  State<BankPage> createState() => _BankPageState();
}
class _BankPageState extends State<BankPage> {
  bool busy = true, master = false;
  num balance = 0;
  String player = 'Jogador', message = '';
  final amount = TextEditingController();
  List<dynamic> pending = [];
  @override
  void initState() { super.initState(); refresh(); }
  Future<void> refresh() async {
    setState(() { busy = true; message = ''; });
    try {
      final p = await db.from('profiles').select('full_name,role,account_status')
        .eq('id', db.auth.currentUser!.id).maybeSingle();
      if (p == null || p['account_status'] != 'approved') {
        setState(() { busy = false; message = 'Sua conta aguarda aprovação do MASTER.'; });
        return;
      }
      player = (p['full_name'] as String?)?.isNotEmpty == true ? p['full_name'] : 'Jogador';
      master = p['role'] == 'master';
      final w = await db.from('game_wallets').select('balance')
        .eq('user_id', db.auth.currentUser!.id).maybeSingle();
      balance = w?['balance'] ?? 0;
      pending = master ? await db.rpc('master_list_balance_requests') : [];
    } catch (e) { message = 'Erro ao carregar: $e'; }
    if (mounted) setState(() => busy = false);
  }
  Future<void> ask() async {
    final v = num.tryParse(amount.text.replaceAll(',', '.'));
    if (v == null || v <= 0) { setState(() => message = 'Informe um valor válido.'); return; }
    try {
      await db.rpc('request_game_balance', params: {'p_amount': v});
      amount.clear();
      setState(() => message = 'Pedido enviado. O saldo só será liberado após aprovação MASTER.');
      await refresh();
    } catch (e) { setState(() => message = 'Erro: $e'); }
  }
  Future<void> decide(dynamic r, String decision) async {
    try {
      await db.rpc('master_review_balance_request', params: {'p_request_id': r['id'], 'p_decision': decision});
      setState(() => message = decision == 'approved' ? 'Créditos virtuais aprovados.' : 'Pedido recusado.');
      await refresh();
    } catch (e) { setState(() => message = 'Erro: $e'); }
  }
  String brl(dynamic n) => 'R\$ ${num.tryParse('$n')?.toStringAsFixed(2) ?? '0,00'}';
  @override
  Widget build(BuildContext context) {
    if (busy) return const Scaffold(body: Center(child: CircularProgressIndicator(color: red)));
    if (message == 'Sua conta aguarda aprovação do MASTER.') return Scaffold(body: Center(child: Padding(
      padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.hourglass_top, color: red, size: 50),
        const Text('Aguardando aprovação', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        Text(message, textAlign: TextAlign.center),
        TextButton(onPressed: refresh, child: const Text('Atualizar')),
        TextButton(onPressed: () => db.auth.signOut(), child: const Text('Sair'))
      ]))));
    return Scaffold(appBar: AppBar(title: const Text('BALLARD BANK'),
      actions: [IconButton(onPressed: refresh, icon: const Icon(Icons.refresh)),
        IconButton(onPressed: () => db.auth.signOut(), icon: const Icon(Icons.logout))]),
      body: RefreshIndicator(onRefresh: refresh, child: ListView(padding: const EdgeInsets.all(18), children: [
        Text('Olá, $player', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 14),
        Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: dark, borderRadius: BorderRadius.circular(20)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('SALDO VIRTUAL', style: TextStyle(color: Colors.white70)),
            Text(brl(balance), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
            const Text('Créditos fictícios do jogo', style: TextStyle(color: Colors.white70))
          ])),
        if (message.isNotEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(message, style: const TextStyle(color: red))),
        if (!master) ...[
          const SizedBox(height: 20),
          const Text('Solicitar saldo', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Valor fictício (R$)')),
          const SizedBox(height: 10),
          FilledButton(onPressed: ask, style: FilledButton.styleFrom(backgroundColor: red),
            child: const Text('ENVIAR PARA APROVAÇÃO MASTER')),
          const Text('Seu saldo não muda até o MASTER aprovar.', style: TextStyle(fontSize: 12, color: Colors.black54))
        ],
        if (master) ...[
          const SizedBox(height: 20),
          const Text('MASTER CONTROL • PEDIDOS PENDENTES', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          if (pending.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Nenhum pedido pendente.')),
          ...pending.map((r) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r['full_name'] ?? 'Jogador', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Pedido: ${brl(r['amount'])}'),
            Text('Jogador: ${r['user_id']}', style: const TextStyle(fontSize: 10)),
            Row(children: [
              Expanded(child: FilledButton(onPressed: () => decide(r, 'approved'),
                style: FilledButton.styleFrom(backgroundColor: red), child: const Text('Aprovar'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton(onPressed: () => decide(r, 'rejected'), child: const Text('Recusar')))
            ])
          ])))),
        ],
        const SizedBox(height: 24),
        const Text('Jogo de banco virtual. Sem PIX, pagamentos ou dinheiro real.',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.black54))
      ])));
  }
}
