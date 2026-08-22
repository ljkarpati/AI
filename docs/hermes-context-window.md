# Hermes Agent: the 40,960 vs 64,000 context crash

## What actually went wrong

There are two failures here, and they need to be untangled before either is
fixed.

**Failure 1 — the real constraint.** `llama-server` reports a 40,960-token
allocation; Hermes Agent refuses anything under 64,000:

```
ValueError: Model qwen3-8b-instruct has a context window of 40,960 tokens,
which is below the minimum 64,000 required by Hermes Agent
```

**Failure 2 — self-inflicted, and currently the blocker.** A hand edit to
`agent_init.py` reflowed the constructor, so `AIAgent.__init__` no longer runs
to completion. That is what produces:

```
AttributeError: 'AIAgent' object has no attribute 'api_mode'
```

This second error is **not** a separate bug to patch around. `api_mode`,
`_memory_store`, `_tool_guardrails`, and `_primary_runtime` are all assigned in
the same `__init__`; `api_mode` is simply the first one something reads
afterwards. Adding an `api_mode` attribute by hand would move the crash to the
next missing attribute, not fix it. Restore the file, then change behaviour
through a mechanism that cannot corrupt syntax.

## Fix order

### Step 1 — put the damaged files back

Network restrictions are not actually in the way. The extracted path
`hermes-agent-2026.8.19\hermes-agent-2026.8.19` is doubled, which is what
`Expand-Archive` produces from a zip — so the original archive is very likely
still in `Downloads`. No re-download required.

```powershell
.\scripts\Repair-HermesInstall.ps1 -Verify     # survey, changes nothing
.\scripts\Repair-HermesInstall.ps1 -Restore    # re-extract and copy back
```

`-Verify` also prints every site enforcing the 64k floor and every config file
under the install root, which is what Step 3 needs.

If the zip is gone: File Explorer → right-click the folder → *Restore previous
versions*, or the Recycle Bin. Do not keep editing the damaged files by hand.

### Step 2 — decide which side of the mismatch to move

The framework wants 64,000 tokens. The server offers 40,960. Either number can
move, but on 8 GB of VRAM they are not equally movable.

A KV cache costs `2 × layers × kv_heads × head_dim × bytes_per_element` per
token. For Qwen3-8B (36 layers, 8 KV heads, head_dim 128) that is 144 KiB per
token at f16. Against ~5 GB of Q4_K_M weights:

| KV cache | @ 40,960 tokens | @ 65,536 tokens |
|---|---|---|
| f16  | 5.62 GB → **10.62 GB** | 9.00 GB → **14.00 GB** |
| q8_0 | 2.99 GB → **7.99 GB**  | 4.78 GB → **9.78 GB**  |
| q5_1 | 2.11 GB → **7.11 GB**  | 3.38 GB → **8.38 GB**  |
| q4_0 | 1.58 GB → **6.58 GB**  | 2.53 GB → **7.53 GB**  |

(Totals include weights but not the compute buffer or CUDA context, together
roughly another 0.5–1 GB.)

Only the bottom-right cell fits 8 GB at all, and it leaves no headroom. **So on
this hardware, reaching a genuine 64k context means q4_0 KV cache plus some
layers pushed to system RAM — a real quality and speed cost.** The 40,960
figure was a sound choice for this card.

That makes the recommendation:

- **Preferred:** keep the server at 40,960 and lower Hermes' floor (Step 3).
- **Only if you need the full window:** raise the server context and accept the
  degradation:

```powershell
.\scripts\Start-LlamaServer.ps1 -ModelPath C:\models\qwen3-8b-instruct-q4_k_m.gguf `
    -ContextSize 65536 -CacheType q4_0 -GpuLayers 32
```

The script prints the VRAM estimate before launching, refuses to start if the
port is already bound, and probes `/props` afterwards to report the context the
server *actually* allocated — which is frequently lower than what was asked for.

Check a server that is already running:

```powershell
.\scripts\Start-LlamaServer.ps1 -ProbeOnly
```

### Step 3 — lower the floor without breaking the source

```powershell
python .\scripts\hermes_ctx_patch.py --root "<install-root>"                       # dry run
python .\scripts\hermes_ctx_patch.py --root "<install-root>" --min-ctx 32768 --apply
python .\scripts\hermes_ctx_patch.py --root "<install-root>" --revert              # undo
```

This is still a patch against vendored source, but it cannot repeat the earlier
failure. It rewrites **only** the integer literal — never a line, never
whitespace — backs up each file, byte-compiles it afterwards, and restores the
backup automatically if the file stops compiling. `1.64000` and `640000` are
left alone; `64_000` is caught. The literal inside the error message is
rewritten too, so the text does not contradict the check.

Set the floor to `32768`, not to something tiny. Hermes' 64k default is not
arbitrary — a long agent loop with tool schemas, history, and retrieved context
genuinely consumes it. At 40,960 you should expect to hit context exhaustion in
long sessions. That is a real constraint of running an 8B model on 8 GB, not
something the patch removes.

**If the script reports no matches**, the floor is declared in `config.yaml` or
another data file rather than in Python. Prefer changing it there — a config
value is not a patch and survives upgrades.

## What is unverified

The blueprint cites `agent_init.py:2782` and `turn_context.py:590`, and a
`config.yaml` under `C:\Users\lemon\Downloads\...`. None of that was inspected:
this work was done in a Linux container that cannot reach your filesystem. The
line numbers, the config schema, and the package layout are all taken from your
report rather than confirmed. `Repair-HermesInstall.ps1 -Verify` is the step
that confirms them; its output is worth reading before applying anything here.
