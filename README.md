# AI Org Orchestrator

**AI Org Orchestrator** is a standalone, local-first platform for managing an LLM-powered agent system.

This repository distributes the compiled, obfuscated CLI (`ai-org`) so you can run the platform directly on your machine.

## 🚀 Installation

Install or update the CLI by running the following command in your terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/FernandoAFaria/ai-org-orchestrator/master/install.sh | bash
```

*This will download the latest release for your platform (macOS/Linux, x64/arm64) and place it in `~/.ai-org`. You may need to restart your terminal or source your `~/.bashrc` / `~/.zshrc` to use the `ai-org` command.*

## ⚙️ Configuration

The orchestrator requires access to OpenRouter to power the AI agents. You will need to provide an API key.

1. Open the configuration file:
   ```bash
   nano ~/.ai-org/.env
   ```
2. Add your OpenRouter API key:
   ```env
   OPENROUTER_API_KEY=your_openrouter_api_key_here
   ```
3. Save and close the file.

*(Note: The database `dev.db` is also stored locally in `~/.ai-org/prisma/dev.db`.)*

## 💻 Usage

Once installed, you can manage the application using the `ai-org` CLI.

### Start the Platform
```bash
ai-org start
```
Starts the Next.js frontend, backend API, and background heartbeat workers. The application will be accessible at:
**http://localhost:8989**

### Stop the Platform
```bash
ai-org stop
```
Safely stops all running Next.js and worker processes.

### View Logs
```bash
ai-org logs
```
Tails the real-time application and worker logs.

### Check Status
```bash
ai-org status
```
Checks if the `ai-org` processes are currently running.

### Update the CLI
```bash
ai-org update
```
Pulls the latest release from GitHub and updates your local installation.

---
*Powered by Bun, Next.js, and OpenRouter.*
