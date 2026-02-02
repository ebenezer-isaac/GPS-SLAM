# GPS-SLAM: Team Quick Start

**Welcome to the team!**
This repository comes with a specific "Zero-Touch" environment to make connecting to UCL GPU machines as painless as possible.

---

## 🚀 Getting Started (2 Minutes)

You do **not** need to install CUDA, Python, or messing with SSH config manually. We use **Dev Containers**.

### 1. Prerequisites
*   **VS Code** + **Dev Containers Extension**.
*   **Docker Desktop** (running).
*   **A Booking**: You must have a booked machine (e.g., `sunstreaker`, `blurr`, etc.).

### 2. Open the Project
1.  Clone this repo:
    ```bash
    git clone --recursive https://github.com/ebenezer-isaac/GPS-SLAM.git
    ```
2.  Open the folder in **VS Code**.
3.  You will see a prompt: **"Reopen in Container"**. Click **Reopen**.
    *   *(This builds your environment with all necessary tools automatically.)*

### 3. First-Time Connection
Once inside the VS Code terminal (Dev Container), run:

```bash
./connect-ucl-remote.sh
```

**It will ask you ONCE:**
1.  **Machine Name**: Enter your booked machine (e.g., `sunstreaker`).
2.  **CS Username**: Enter your UCL ID (e.g., `zcav...`).
3.  **Password**: Your CS password.

> **Magic ✨**: It will automatically generate SSH keys, copy them to the server, and save your preferences locally. You won't need to type your password again.

---

## ⚡ Daily Workflow

After the first setup, just run:

```bash
./connect-ucl-remote.sh
```

It will instantly connect you to your booked machine.

### Need to change machines?
If you book a *different* machine next time, just run with arguments to update your config:

```bash
# Updates your default machine to 'brawl'
./connect-ucl-remote.sh brawl
```

---

## 🛠 Advanced Features

### Run Remote Commands
You can run GPU checks or other commands without logging in interactively:

```bash
./connect-ucl-remote.sh "nvidia-smi"
./connect-ucl-remote.sh "htop"
```

### Manual/Local Setup
*(Only if you can't use Docker)*
Use the scripts in `ucl-tools/` directly on your host (Linux/WSL):
1.  `./ucl-tools/setup_keys.sh` (One time setup)
2.  `./ucl-tools/connect_local.sh` (Connect)

---

## ❓ FAQ

**Q: Where is my password saved?**
A: It is stored in `.connection_config` inside the `ucl-tools` folder. This file is **git-ignored**, so your credentials will **never** be shared with the team when you push changes.

**Q: "Address already in use"?**
A: We use connection sharing to make things fast. This warning is harmless.

**Q: Double Password Prompt?**
A: This means your SSH keys aren't on the server. The script should fix this automatically, but you can force it by running `./ucl-tools/setup_keys.sh`.
