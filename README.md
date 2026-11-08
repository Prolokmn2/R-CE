# R-CE v2 — Roblox Cheat Engine

A full-featured script-introspection and debugging toolkit with a classic-debugger dark UI.

## Important: authorized use only

R-CE is intended only for debugging Roblox experiences that you own or are explicitly authorized to test, in a private development environment. Do not use it to inspect, interfere with, or gain an advantage in games or services you do not own. Do not use it to bypass access controls, extract private or server-only data, or disrupt other players.

Some debugging operations can change runtime state, execute code, or expose sensitive information. Use them only with explicit authorization and with backups of anything important. You are responsible for complying with applicable laws, Roblox's terms and policies, and any project agreements. This disclaimer does not grant permission to access any game or system and does not guarantee that use of this project is safe or permitted.

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

Use only in a private development environment for an experience you own or are authorized to test. `RightShift` hides/shows the window.

Best Debuger out there right now
this debugger is made so you can debug and fix stuff in your game 

## New in v2

- **Remote Spy** tab (FireServer / InvokeServer / Bindable)
- **HTTP Spy** tab (HttpService + executor http functions)
- **Event Spy** tab (BindableEvent / BindableFunction monitoring)
- **Exec** tab (script editor + output console + Invoke Remote)
- **Explorer** tab (DEX++ style with icons + ServerStorage gc peek)
- **Live View** tab (unified real-time event stream)
- **Multi-type memory scanner** (number, string, bool, integer, any)
- Re-fire script generator in Remote Spy
- Auto-wires all spies when Live View is enabled

## License

This project is distributed under the GNU General Public License, version 3. See [LICENSE](./LICENSE) for the full license text.
