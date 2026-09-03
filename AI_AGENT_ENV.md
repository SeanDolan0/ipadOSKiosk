# AI_AGENT_ENV — Local Quantized Qwen 27B Agent Environment

> **READ THIS FIRST.** Authoritative resume point for this branch
> (`qwen-local-agent`). Any Claude Code / opencode / Pi session picks up here.

**Branch purpose** (per user): run a **local, quantized LLM agent** isolated on its
own branch so a smaller/riskier model cannot corrupt the Gecko rewrite work on
`Gecko-Rewrite`. This branch is a fork of `Gecko-Rewrite` (the Gecko handoff docs
are present, but the engine work lives on `Gecko-Rewrite`; treat this branch as
experimental sandbox only).

## 1. TL;DR — what runs here

| Piece | What | Status |
|---|---|---|
| Model | `unsloth/Qwen3.8-27B-GGUF` → `Qwen3.8-27B-UD-Q2_K_XL.gguf` (9.83 GB, Q2_K_XL Unsloth Dynamic) | Ready to download via `download-model.ps1` |
| Runtime | **llama.cpp** `llama-server` (WinGet: `ggml.llamacpp` v0.1.2-dev build 10507, Vulkan backend) | installed, verified |
| GPU | **NVIDIA GeForce RTX 5070 Ti Laptop GPU** (12 GB VRAM, Vulkan device `Vulkan1`) | detected, verified |
| Context | 64k (`-c 65536`) with quantized KV cache (`-ctk q8_0 -ctv q8_0`) | default 64k context |
| Harness (Mac) | **opencode** (headless `opencode run --model local/qwen3.8 --auto`) | configured in `ralph-gecko/ralph.sh` |
| Loop | **Ralph loop** (`ralph-gecko/ralph.sh`) | configured with pre-flight check |

The whole flow:
1. **Windows**: Run `download-model.ps1` → `serve.ps1` (listens on `0.0.0.0:8085` by default, offloading to RTX 5070 Ti).
2. **Mac**: Set `WINDOWS_IP=192.168.x.y` (and `PORT=8085`) → run `./ralph.sh` inside `ralph-gecko/`.

## 2. One-time setup (Windows Host)

```powershell
# 1) Get the model (~9.83 GB). Run from repo root.
powershell -ExecutionPolicy Bypass -File .\scripts\agent\download-model.ps1

# 2) Allow inbound port 8085 through Windows Defender Firewall (Run in Admin PowerShell once):
netsh advfirewall firewall add rule name="llama-server 8085" dir=in action=allow protocol=TCP localport=8085

# 3) Start the server (opens llama-server in its own window)
powershell -ExecutionPolicy Bypass -File .\scripts\agent\serve.ps1
```

## 3. Running the Ralph Loop from the Mac

On your Mac:
```bash
cd ralph-gecko
export WINDOWS_IP=192.168.50.177   # (or the LAN IP printed by serve.ps1)
export PORT=8085                   # must match serve.ps1 --port (default 8085)
./ralph.sh 50
```

`ralph.sh` will:
- Verify network reachability to `http://${WINDOWS_IP}:${PORT}/v1/models`.
- Write local `opencode.json` pointing the `local/qwen3.8` provider to your Windows machine.
- Drive `opencode run --model local/qwen3.8 --auto "$(cat PROMPT.md)"` headless with fresh context per iteration.

## 4. Hardware envelope (this Windows box, verified)
- **RAM**: 32 GB system memory.
- **GPU**: NVIDIA GeForce RTX 5070 Ti Laptop GPU (12 GB VRAM).
- **Vulkan Devices**:
  - `Vulkan0`: Intel(R) Graphics (integrated)
  - `Vulkan1`: NVIDIA GeForce RTX 5070 Ti Laptop GPU (discrete)
- **Engine settings**:
  - `-dev Vulkan1`: Forces offloading to RTX 5070 Ti instead of Intel graphics.
  - `-ngl 99`: Offloads all model layers into GPU memory.
  - `-c 65536`: 64k context window.
  - `-ctk q8_0 -ctv q8_0`: Quantizes KV cache (use `q4_0` if VRAM is tight with 64k).
- **LAN IP**: `192.168.50.177` (Ethernet) or `192.168.50.139` (Wi-Fi).

## 5. Files in this branch
```
scripts/agent/
  download-model.ps1     # fetch GGUF from Hugging Face (--ssl-no-revoke supported)
  serve.ps1              # llama-server on 0.0.0.0:8085 using RTX 5070 Ti (Vulkan1)
  start-opencode.ps1     # verify server + launch opencode locally
ralph-gecko/
  ralph.sh               # Mac-side Ralph loop runner (auto-configures opencode.json)
  PROMPT.md              # per-iteration prompt
  AGENTS.md              # instructions & operational constraints
  IMPLEMENTATION_PLAN.md # living checklist
  progress.md            # append-only run log
AI_AGENT_ENV.md          # this file
models/                  # (gitignored) where the 9.83 GB GGUF lands
```

## 6. Status / next steps
- [ ] Run `download-model.ps1` to fetch `Qwen3.8-27B-UD-Q2_K_XL.gguf`.
- [ ] Run `serve.ps1` and verify `http://127.0.0.1:8085/v1/models` returns model JSON.
- [ ] Run the firewall command if inbound traffic from Mac is blocked.
- [ ] On the Mac, run `ralph-gecko/ralph.sh`.

## 7. Rules (user requirements)
- This branch is experimental sandbox. Do NOT merge experiment cruft back into
  `Gecko-Rewrite` or `master`.
- Commit meaningful steps; keep this doc + docs current so any session resumes cold.
- The 9.83 GB `.gguf` is gitignored and MUST never be committed.
