# GitHub Remote Setup

Quando houver a URL do repositório no GitHub, conecte este repositório local com:

```bash
git remote add origin <URL_DO_REPOSITORIO_GITHUB>
git push -u origin main
```

Se quiser trocar a identidade local usada neste repositório antes do push:

```bash
git config user.name "SEU_NOME"
git config user.email "SEU_EMAIL"
```
