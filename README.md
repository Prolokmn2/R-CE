# R-CE v2 — Roblox Cheat Engine

A full-featured script-introspection and debugging toolkit with a classic-debugger dark UI.

## Tabs

| Tab | What it does |
|---|---|
| **Memory** | Value scanner over the Lua heap — now supports **number, string, bool, integer, any**. First/Next scan, Set, Freeze/Thaw. Plus hex heap viewer. |
| **GC Closures** | Crawls `getgc()`, shows constants/upvalues, one-click Hook, jump to bytecode. |
| **Bytecode** | Lists scripts, Luau disassembler + decompiler. |
| **Hooks** | Remote logger + require() logger + per-closure hooks. |
| **Remote Spy** | Intercepts `FireServer`, `InvokeServer`, Bindable:Fire via `__namecall`. Shows args, generates re-fire scripts. |
| **HTTP Spy** | Hooks `HttpService` + `syn.request` / `http.request`. Shows URL, body, headers, response. |
| **Event Spy** | Monitors `BindableEvent:Fire` / `BindableFunction:Invoke`. Scan+Watch All button. |
| **Exec** | Full script editor with output capture, history, and a one-click Invoke Remote. |
| **Explorer** | DEX++ style instance tree with icons, properties panel, source viewer. Tries to peek **ServerStorage / ServerScriptService** via gc scan + getrenv. |
| **Live View** | Unified real-time feed of everything — remotes, http, events, hooks — with per-kind toggles and text filter. |

## Run

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Prolokmn2/R-CE/main/loader.lua"))()
```

`RightShift` hides/shows the window.

## New in v2

- 🆕 **Remote Spy** tab (FireServer / InvokeServer / Bindable)
- 🆕 **HTTP Spy** tab (HttpService + executor http functions)
- 🆕 **Event Spy** tab (BindableEvent / BindableFunction monitoring)
- 🆕 **Exec** tab (script editor + output console + Invoke Remote)
- 🆕 **Explorer** tab (DEX++ style with icons + ServerStorage gc peek)
- 🆕 **Live View** tab (unified real-time event stream)
- 🆕 **Multi-type memory scanner** (number, string, bool, integer, any)
- 🆕 Re-fire script generator in Remote Spy
- 🆕 Auto-wires all spies when Live View is enabled
