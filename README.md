# AI

## Hermes Agent — local debugging tooling

Tooling for running Nous Research's Hermes Agent against a local
`llama-server` backend on constrained VRAM.

Start here: **[docs/hermes-context-window.md](docs/hermes-context-window.md)** —
diagnosis of the `ValueError` context-window crash and the follow-on
`AttributeError: 'AIAgent' object has no attribute 'api_mode'`, plus the order
to fix them in.

| Script | Purpose |
|---|---|
| `scripts/Repair-HermesInstall.ps1` | Restore hand-edited source from the original archive; locate where the 64k floor is enforced. |
| `scripts/inspect_config.py` | Report and sanity-check the endpoint / context / model fields in `config.yaml`. Read-only. |
| `scripts/Start-LlamaServer.ps1` | Launch `llama-server` with a VRAM estimate up front; verify the context it actually allocated. |
| `scripts/hermes_ctx_patch.py` | Lower the minimum-context floor by rewriting the integer literal only, with backup, compile check, and automatic rollback. |

The Python scripts are tested. The PowerShell scripts were authored in a Linux
container with no PowerShell available, so their syntax is unverified — read
them before running, and use the `-Verify` / `-DryRun` / `-ProbeOnly` modes
first.
