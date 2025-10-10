# ProjetoARCA

## Repositório no drive
* [Home](https://link-para-o-drive-removido)

    * [Administrativo](https://link-para-o-drive-removido)
    * [Artigos e pesquisas](https://link-para-o-drive-removido)
    * [Marketing](https://link-para-o-drive-removido)
    * [Modelagem 3D](https://link-para-o-drive-removido)
    * [Planejamentos](https://link-para-o-drive-removido)
    * [Outros](https://link-para-o-drive-removido)

## Artigo
   [Link para artigo no overleaf](https://link-para-o-artigo-removido)
   

# 🧩 Guia de Contribuição - Como Contribuir como Desenvolvedor

Bem-vindo(a) ao projeto! 🎉  
Ficamos muito felizes com o seu interesse em contribuir.  
Este guia te ajudará a configurar todo o ambiente de desenvolvimento necessário para compilar e rodar o projeto localmente.

---

## 🚀 Passo 1: Instalar o Git

O Git é o sistema de controle de versão que usamos para gerenciar o código-fonte.

**O que fazer:**  
Baixe e instale o Git para o seu sistema operacional.

🔗 [Download do Git](https://git-scm.com/downloads)

---

## 🧰 Passo 2: Instalar o Flutter SDK

O Flutter é o kit de desenvolvimento principal, contendo todas as ferramentas para compilar e criar o aplicativo.

**O que fazer:**  
Siga o guia oficial para baixar o SDK e **adicione o `flutter/bin` ao PATH** do sistema, conforme instruído.

🔗 [Documentação Oficial de Instalação do Flutter](https://docs.flutter.dev/get-started/install)

---

## 📱 Passo 3: Instalar o Android Studio e o Android SDK

O Android Studio fornece o SDK necessário para compilar e rodar o aplicativo em dispositivos Android.

**O que fazer:**  
1. Baixe e instale o Android Studio.  
2. Ao abrir pela primeira vez, siga o assistente de instalação do Android SDK.  
3. No SDK Manager (`More Actions > SDK Manager`), vá até **SDK Tools** e marque as opções:
    - **Android SDK Command-line Tools (latest)**, .
    - **NDK (side by side)**
    - **CMake**

🔗 [Download do Android Studio](https://developer.android.com/studio)

---

## ⚙️ Passo 4: Configurar Variáveis de Ambiente do Android

O Flutter precisa saber onde está o Android SDK instalado.

**O que fazer:**  
Crie a variável de ambiente `ANDROID_HOME` apontando para o local onde o Android SDK foi instalado.

🔗 [Guia de Configuração para Android (Flutter)](https://docs.flutter.dev/get-started/install/linux#android-setup)

---

## 💻 Passo 5: Instalar o Visual Studio Code (VS Code)

Editor de código recomendado para o desenvolvimento em Flutter.

**O que fazer:**  
Baixe e instale o VS Code.

🔗 [Download do VS Code](https://code.visualstudio.com/)

---

## 🔌 Passo 6: Instalar a Extensão do Flutter no VS Code

A extensão integra o Flutter ao VS Code, permitindo rodar, depurar e ter autocompletar de código.

**O que fazer:**  
1. Abra o VS Code.  
2. Vá até a aba de Extensões (ícone de blocos no menu lateral).  
3. Pesquise por **Flutter** e instale a extensão oficial (publicada por *Dart Code*).  
4. A extensão do Dart será instalada automaticamente.

---

## 🩺 Passo 7: Verificar a Instalação com `flutter doctor`

O Flutter possui uma ferramenta que verifica se o ambiente está corretamente configurado.

**O que fazer:**  
Abra o terminal e rode o comando:

```bash
flutter doctor -v
```

Se houver algum problema ([✗] ou [!]), o comando geralmente sugere como corrigir (exemplo: `flutter doctor --android-licenses`).

---

## 📂 Passo 8: Obter o Código do Projeto

Com o ambiente pronto, é hora de baixar o código-fonte do projeto.

**O que fazer:**  
1. Faça um **Fork** do repositório no GitHub.  
2. Clone o seu fork localmente:

```bash
git git@github.com:gabriel26077/ProjetoARCA.git
cd ProjetoARCA/micro_arca_app
```

---

## 🧠 Passo 9: Fluxo de Trabalho com Git Flow

Para manter a organização e integridade do projeto, seguimos um fluxo de desenvolvimento baseado em **Git Flow**.

**Regras básicas:**

- **Nunca faça push direto** nas branches `main` ou `dev`.  
- Sempre crie uma **branch de feature** a partir da `dev`.

### Criando uma branch de feature

```bash
git checkout dev
git pull
git checkout -b feature/nome-da-feature
```

### Após finalizar sua feature

1. Faça o commit e push da sua branch:

```bash
git add .
git commit -m "Descrição da feature"
git push origin feature/nome-da-feature
```

2. Crie um **Merge Request (MR)** ou **Pull Request (PR)** para a branch `dev`.  
3. Seu MR será analisado por outros desenvolvedores.  
4. Se estiver tudo certo ✅, será integrado e a *issue* será encerrada.  
5. Caso haja ajustes necessários ❌, a *issue* retornará com instruções de correção.

---

## ▶️ Passo 10: Rodar o Projeto

**O que fazer:**  
1. Baixe as dependências:

```bash
flutter pub get
```

2. Conecte um dispositivo físico ou inicie um emulador.  
3. Rode o aplicativo:

```bash
flutter run
```

---

🎉 **Pronto!** Seu ambiente está configurado e você pode começar a contribuir com o projeto!  
Lembre-se: código limpo, commits descritivos e respeito ao fluxo Git são fundamentais para o sucesso coletivo.