# Ativar login e compartilhamento

O dashboard já está conectado ao projeto Supabase e contém o fluxo de login, sincronização, convites e controle de acesso aos valores. A URL e a chave pública publishable ficam no HTML; elas não são segredos. A segurança dos dados depende das políticas/RPCs do SQL e da chave administrativa ficar apenas na Edge Function.

## 1. Configurar o banco

No projeto **Controle Financeiro Brasil** (`https://vyyhlhbsmzoglwfzccri.supabase.co`), abra **SQL Editor → New query** e execute o arquivo [`supabase/schema.sql`](supabase/schema.sql). Depois, abra outra query, substitua `EMAIL_DO_PABLO` pelo e-mail de login no arquivo [`supabase/bootstrap-owner.sql`](supabase/bootstrap-owner.sql) e execute-o para autorizar a conta principal como **Pablo**.

Não marque “Automatically expose new tables”. Não é necessário criar tabelas manualmente. O SQL cria as tabelas, habilita RLS e bloqueia acesso direto ao banco.

## 2. Ativar a conta Pablo

Abra o dashboard e escolha **Recebi um convite / primeiro acesso**. Informe o e-mail autorizado e crie uma senha forte, única, com pelo menos 12 caracteres. Se a confirmação de e-mail estiver ativada, confirme a mensagem que o Supabase enviar e depois entre pela tela de login. Não use a senha `123`.

Se o cadastro informar que o e-mail precisa de confirmação, verifique também Spam/Lixo eletrônico. Confirme que o provedor **Email** está ativo em **Authentication → Sign In / Providers**.

## 3. Publicar para acessar em outros dispositivos

O arquivo aberto em `file://` funciona apenas no dispositivo onde está salvo e não é um endereço adequado para os links de convite. Publique o `index.html` em um site HTTPS. Em seguida, no Supabase abra **Authentication → URL Configuration** e defina a URL publicada como **Site URL** e em **Redirect URLs**. Atualize a mesma URL no segredo `APP_REDIRECT_URL` da Edge Function.

## 4. Habilitar convites de convidados

O botão **Acessos** já está no dashboard do responsável, mas o envio de e-mail precisa que a Edge Function seja implantada. Na pasta do projeto, use o Supabase CLI para fazer deploy de `supabase/functions/invite-user` com o nome `invite-user`. Configure os secrets da função no Supabase:

- `SUPABASE_PUBLIC_KEY`: chave publishable pública deste projeto.
- `SUPABASE_SECRET_KEY`: chave secret do projeto. Ela fica somente nos secrets da função; nunca no HTML, GitHub ou navegador.
- `APP_REDIRECT_URL`: URL HTTPS publicada do dashboard.

`SUPABASE_URL` já é fornecida automaticamente ao runtime das Edge Functions. Ao convidar alguém, escolha se essa pessoa poderá ver valores. Usuários sem essa permissão recebem os valores financeiros ocultos e ficam em modo somente leitura.

## Observações

- O banco compartilhado é a fonte de dados; o IndexedDB continua sendo um cache local do navegador.
- No primeiro login em um dispositivo com dados locais, o dashboard pergunta se você deseja migrá-los. Só confirme se esses são os dados corretos; isso envia os lançamentos ao banco compartilhado.
- Se o SQL ainda não tiver sido executado, o login não encontrará o perfil autorizado. Execute os dois arquivos SQL antes de ativar a conta.
- Guarde a senha do banco e qualquer chave `secret` fora do código-fonte.
