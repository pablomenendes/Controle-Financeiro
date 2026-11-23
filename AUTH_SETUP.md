# Login e compartilhamento

O dashboard usa o Supabase para proteger os dados, sincronizá-los entre dispositivos e aplicar permissões. O login agora é somente por e-mail e senha; não há cadastro público nem confirmação por e-mail no fluxo normal.

## 1. Preparar a conta principal

No projeto **Controle Financeiro Brasil** (`https://vyyhlhbsmzoglwfzccri.supabase.co`), confirme que o esquema já foi instalado. Se não, execute [`supabase/schema.sql`](supabase/schema.sql) no **SQL Editor**.

Em **Authentication → Users**, crie ou localize `pablomenendes10@gmail.com`. Se for criar, defina uma senha forte e marque o e-mail como confirmado; não é necessário enviar e-mail. Depois, execute [`supabase/bootstrap-owner.sql`](supabase/bootstrap-owner.sql) no SQL Editor para vincular a conta ao perfil responsável.

Se o endereço já existir, execute o bootstrap para vincular o perfil existente. Se a senha não for conhecida, use a recuperação depois que o limite de e-mails liberar. Remova e recrie uma conta somente se ela for uma conta de teste sem uso; o estado financeiro compartilhado não é apagado ao remover um usuário.

Não marque “Automatically expose new tables”. O SQL cria tabelas, habilita RLS e bloqueia acesso direto ao banco.

## 2. Publicação e redirecionamento

O dashboard deve estar publicado em HTTPS para funcionar em outros dispositivos. Em **Authentication → URL Configuration**, mantenha a URL publicada como **Site URL** e em **Redirect URLs**. O novo fluxo de criação direta não depende de `APP_REDIRECT_URL`.

## 3. Criar e administrar convidados sem e-mail

No painel **Acessos**, Pablo pode criar uma conta com e-mail, nome, senha inicial e permissão para ver valores; redefinir a senha de convidados; e desativar ou reativar acessos. As senhas devem ter ao menos 12 caracteres e ser compartilhadas por um canal privado. O site não guarda nem exibe as senhas depois da criação.

Para ativar esse fluxo, publique a versão atualizada da Edge Function `invite-user` usando o Supabase CLI. Configure os secrets:

- `SUPABASE_PUBLIC_KEY`: chave publishable do projeto.
- `SUPABASE_SECRET_KEY`: chave secret do projeto. Ela fica apenas nos secrets da função; nunca no HTML, GitHub ou navegador.

`SUPABASE_URL` é fornecida automaticamente ao runtime das Edge Functions. `APP_REDIRECT_URL` não é necessário para criar contas nem redefinir senhas.

## Observações

- Apenas o responsável cria contas; visitantes não conseguem se cadastrar para acessar o dashboard.
- Usuários sem permissão para ver valores recebem uma visão somente leitura com os valores ocultos.
- O banco compartilhado é a fonte de dados; o IndexedDB continua como cache local do navegador.
- No primeiro login de um dispositivo com dados locais, o dashboard pergunta se deseja migrá-los. Só confirme se forem os dados corretos.
- A chave `secret` do Supabase deve permanecer somente nos secrets da Edge Function.
