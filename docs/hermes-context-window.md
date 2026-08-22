# Hermes Agent on a local llama-server: correct setup

> **This document supersedes an earlier version in this repo.** That version
> assumed the extracted zip was the install and told you how to patch it. That
> premise was wrong. Hermes Agent ships an installer, and almost every error in
> this session traces back to bypassing it.

## The actual root cause

Running `python run_agent.py` from an extracted
`hermes-agent-2026.8.19.zip` is not a supported way to start Hermes Agent.
The consequences showed up one at a time and looked like unrelated bugs:

| Symptom | Real cause |
|---|---|
| `ModuleNotFoundError: No module named 'nemo_relay'` | Dependencies were never installed — only `fire`, `openai`, etc. were added by hand as each ImportError appeared. |
| `ValueError: ... below the minimum 64,000` | A genuine, documented requirement. Not a bug. |
| `AttributeError: ... no attribute 'api_mode'` | A hand edit truncated `AIAgent.__init__`. |
| `AttributeError: ... no attribute '_compression_warning'` | The stub replacement for `agent_init.py` sets 6 attributes; the real one sets many more. |

The last two are the same error twice. Replacing `agent_init.py` with a stub
that fakes attributes cannot converge: every attribute the real `__init__`
sets has to be discovered by crashing on it. `_compression_warning` was next;
after it there is another, and another.

Also note the interpreter: `C:\Python314\`. **Hermes Agent targets Python
3.11**, which its installer provisions through `uv`. Running it on 3.14 with
packages hand-installed into `AppData\Roaming\Python\Python314\site-packages`
is a second, independent source of breakage.

## Fix: install it properly

Everything else follows from this. On Windows PowerShell:

```powershell
iex (irm https://hermes-agent.nousresearch.com/install.ps1)
```

This provisions `uv`, Python 3.11, Node.js v22, ripgrep and ffmpeg, and lands a
managed install at `C:\Users\lemon\.hermes\hermes-agent`. Then:

```powershell
hermes doctor
```

`hermes doctor` is the supported diagnostic and should complete cleanly before
anything else is attempted.

Once installed, **delete the Downloads copy** — or at least stop running
anything from it. Keeping a hand-modified source tree next to a managed
install is how you end up debugging the wrong file. The stubbed
`agent_init.py` is not worth salvaging.

> The install line pipes a remote script straight into execution. That is the
> vendor's documented method, but it does mean trusting that URL at run time.
> If you would rather inspect it first, `irm https://hermes-agent.nousresearch.com/install.ps1 -OutFile install.ps1`,
> read it, then run it. If the earlier network restrictions block the fetch,
> that has to be resolved first — there is no supported offline install.

## Config lives somewhere else than you were editing

Hermes reads `~/.hermes/config.yaml` — on your machine
`C:\Users\lemon\.hermes\config.yaml`. Secrets go to `~/.hermes\.env`.

The `config.yaml` inside the Downloads folder is not the operative config. Time
spent editing it was wasted, which is worth knowing before you spend more.

Set values through the CLI so they land in the right file:

```powershell
hermes model                       # interactive; choose "Custom Endpoint"
hermes config set <key> <value>
```

For a local OpenAI-compatible server the relevant settings are
`CUSTOM_BASE_URL` and `CUSTOM_API_KEY` (the key may be any placeholder for a
local endpoint).

## The base_url has been wrong the whole time

```
--base_url="http://127.0.0"
```

`127.0.0` is three octets. It is not a valid IPv4 address, so every request
against it fails regardless of anything else. It needs to be:

```
http://127.0.0.1:8080/v1
```

This appeared in the original blueprint and is still in the command line being
run. Fixing the install will not fix this; it has to be corrected explicitly.

## The 64k floor is a real requirement — meet it, don't patch it

The Hermes docs are explicit: *"Hermes Agent requires a model with at least
64,000 tokens of context"*, and for local models, *"set its context size to at
least 64K (e.g. `--ctx-size 65536` for llama.cpp)"*.

So the floor is a supported, intentional constraint, not a factory default to
be filed off. The question is whether your card can meet it.

A KV cache costs `2 × layers × kv_heads × head_dim × bytes_per_element` per
token. For Qwen3-8B (36 layers, 8 KV heads, head_dim 128) that is 144 KiB per
token at f16. Against ~5 GB of Q4_K_M weights, at 65,536 tokens:

| KV cache | KV size | + weights |
|---|---|---|
| f16  | 9.00 GB | **14.00 GB** |
| q8_0 | 4.78 GB | **9.78 GB** |
| q5_1 | 3.38 GB | **8.38 GB** |
| q4_0 | 2.53 GB | **7.53 GB** |

(Excludes the compute buffer and CUDA context — roughly another 0.5–1 GB.)

**Only q4_0 fits 8 GB, and it leaves no headroom.** So 64k is reachable on your
hardware, but only with a quantised KV cache and probably a few layers pushed
to system RAM:

```powershell
llama-server --model C:\models\qwen3-8b-instruct-q4_k_m.gguf `
  --ctx-size 65536 --flash-attn `
  --cache-type-k q4_0 --cache-type-v q4_0 `
  --n-gpu-layers 32 --host 127.0.0.1 --port 8080
```

`--flash-attn` is required for a quantised V cache. Drop `--n-gpu-layers` further
if it OOMs. `scripts/Start-LlamaServer.ps1` prints this estimate before
launching and then probes `/props` to report the context actually allocated,
which is often lower than requested.

If q4_0 quality proves unacceptable, the honest options are a smaller model
(so the weights leave more room for cache) or more VRAM — not a lower floor.

## Getting the web dashboard up

This is what you were reaching for with the Vite build on ports 5173/9999.
Those were the wrong target — the dashboard is served by Hermes itself:

```powershell
cd $env:USERPROFILE\.hermes\hermes-agent
uv pip install -e ".[web,pty]"     # base install has no HTTP layer
hermes doctor
hermes dashboard                    # http://127.0.0.1:9119
```

Notes:

- **9119** is the default port, not 9999 or 5173.
- The `web` extra pulls in FastAPI/Uvicorn; without it the dashboard cannot
  start. `[all]` installs everything.
- `pty` (embedded chat terminal) is POSIX-only, so on Windows expect
  `".[web]"` to be the useful target if `pty` fails to build.
- Don't use `hermes dashboard --port 8080` — that collides with llama-server.
- On loopback there's no auth. Binding `--host 0.0.0.0` requires configuring an
  auth provider first; the server refuses to start otherwise. Leave it on
  127.0.0.1 unless you specifically need remote access.

## About `hermes_ctx_patch.py`

That script is still in this repo, but given the above it should be treated as
a last resort for experimentation only. Lowering a documented hard minimum
means running the agent in a regime its authors excluded; expect degraded
behaviour and context exhaustion in long tool-calling loops rather than a clean
failure. Meet the 64k requirement instead.

## Sources

- [Installation](https://hermes-agent.nousresearch.com/docs/getting-started/installation)
- [Quickstart](https://hermes-agent.nousresearch.com/docs/getting-started/quickstart)
- [Web Dashboard](https://hermes-agent.nousresearch.com/docs/user-guide/features/web-dashboard)
- [NousResearch/hermes-agent](https://github.com/nousresearch/hermes-agent)
