# Cadastro do App Android da Unity no Firebase

Este repositório nao inclui um `google-services.json` real. O arquivo verdadeiro depende do cadastro do app Android no projeto Firebase com o package name exato da build Unity para Meta Quest.

## O que a equipe precisa informar

- `Bundle Identifier` / `package name` Android do projeto Unity

Exemplo:

- `br.senai.tutorvr`
- `com.senai.ambiente3d`

Esse valor deve ser exatamente o mesmo usado no Unity em `Build Settings > Android > Player Settings > Other Settings`.

## Como gerar o arquivo real no Firebase

1. Abrir o projeto Firebase correto na conta Google do SENAI.
2. Ir em `Configuracoes do projeto`.
3. Na secao `Seus apps`, clicar em `Adicionar app`.
4. Escolher `Unity` e selecionar `Android` como build target.
5. Informar o `Android package name` exatamente igual ao `Bundle Identifier` do projeto Unity.
6. Registrar o app.
7. Baixar o arquivo `google-services.json`.

## Como usar no projeto Unity

1. Colocar o arquivo real `google-services.json` dentro de `Assets/`.
2. Importar os pacotes do Firebase Unity SDK necessarios.
3. Inicializar o Firebase antes de usar Auth, Firestore, Functions e App Check.

## App Check

Esta solucao atual depende de `Firebase ID Token` e `App Check Token` para chamadas ao backend. Portanto, apos cadastrar o app Android, a equipe tambem deve registrar o app em `App Check` no Firebase Console.

Para Meta Quest, o fluxo relevante e Android. Se houver uso adicional de Desktop/Editor, isso deve ser tratado separadamente conforme a documentacao oficial do Firebase Unity.

## Arquivo de exemplo

O arquivo [google-services.example.json](/mnt/c/Users/RafaelSharkatech/Dev/Projects/SENAI%20-%20GIZ/senai_2026_alpha_01%20-%20para%20SENAI/docs/google-services.example.json) foi derivado de um `google-services.json` real gerado no Firebase e depois sanitizado para publicacao. Ele existe apenas para mostrar a estrutura esperada e nao deve ser usado em producao.
