# AI

## Hermes Agent — local setup on a llama-server backend

Notes and tooling for running [Hermes Agent](https://github.com/nousresearch/hermes-agent)
(Nous Research) against a local `llama-server` on a consumer GPU.

**Start here: [docs/hermes-context-window.md](docs/hermes-context-window.md).**
It covers why running `python run_agent.py` from an extracted zip produces a
cascade of unrelated-looking errors, how to install properly, how to meet the
documented 64,000-token context minimum on 8 GB of VRAM, and how to bring up
the web dashboard.

| Script | Purpose |
|---|---|
| `scripts/Start-HermesDashboard.ps1` | Verify the install end to end (CLI, managed tree, `[web]` extra, backend context, base_url, `hermes doctor`), then start the dashboard on 127.0.0.1:9119. |
| `scripts/Start-LlamaServer.ps1` | Launch `llama-server` with a VRAM estimate up front; probe `/props` for the context actually allocated. |
| `scripts/inspect_config.py` | Read-only report of endpoint / context / model fields in a `config.yaml`. |
| `scripts/Repair-HermesInstall.ps1` | Restore hand-edited source from the original archive. Superseded by a clean reinstall; kept for recovering a modified tree. |
| `scripts/hermes_ctx_patch.py` | **Last resort.** Lowers the minimum-context floor by rewriting the integer literal only, with backup and automatic rollback. The 64k floor is a documented requirement — prefer meeting it. |

The Python scripts are tested. The PowerShell scripts were authored in a Linux
container with no PowerShell available, so their syntax is unverified — read
them before running and use `-CheckOnly` / `-DryRun` / `-ProbeOnly` first.
