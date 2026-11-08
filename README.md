# R-CE — Roblox Cheat Engine

A lightweight script-introspection toolkit with a classic-debugger dark UI.

| Tab | What it does |
|---|---|
| **Memory** | Cheat-Engine style value scanner over the Lua heap (table fields + closure upvalues): First Scan, Exact / Changed / Same / Up / Down, Set, Freeze. Plus a heap viewer (`allocm` / `readmem` / `writemem`) with hexdump and hex writes. |
| **GC Closures** | Crawls `getgc()` (manual or auto every 3 s), blacklists UI/engine packages, shows constants + upvalues, one-click **Hook**, jump to the owning script's bytecode. Filter by name/path, or `k:text` to search constants. |
| **Bytecode** | Lists scripts, runs `getscriptbytecode` through a built-in Luau disassembler (`OP_GETIMPORT`, `OP_CALL`, `OP_LOADK` ... with constants, imports, jump targets and line numbers), or `decompile`. |
| **Hooks** | Remote spy (`FireServer`/`InvokeServer` via `__namecall`), `require` logger, and per-closure hooks that log args, returns, constants and upvalues. |

## Run

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Prolokmn2/R-CE/main/loader.lua"))()
```

`RightShift` hides/shows the window. Re-running the loader cleanly unloads the previous instance.

Local testing (files in your executor workspace under `R-CE/`):

```lua
getgenv().RCE_LOCAL = true
loadstring(readfile("R-CE/loader.lua"))()
```

## Layout

```
loader.lua                 entry point + module loader (RCE.require)
src/core/Env.lua           capability detection (every executor function resolved once)
src/core/Util.lua          serializer, hexdump, clipboard
src/core/Registry.lua      state bridge in debug.getregistry() (falls back to getgenv)
src/core/Memory.lua        heap bridge: allocm/readmem/writemem, buffer fallback, JSON persistence
src/modules/GC.lua         getgc closure scanner + blacklist
src/modules/ValueScan.lua  numeric scanner / setter / freezer
src/modules/Hooks.lua      namecall, require and closure hooks
src/modules/Bytecode.lua   Luau bytecode parser + disassembler
src/ui/UI.lua              window, tabs, widgets
```

## Notes

- `allocm`, `readmem`, `writemem` are **not** standard UNC functions. At startup R-CE self-tests them
  (`allocm(n)` -> addr, `writemem(addr, string)`, `readmem(addr, n)` -> string). If they are missing or
  behave differently, it silently falls back to Luau `buffer` blocks. Adjust `Memory.lua` if your executor's
  signatures differ.
- The status bar lists any missing functions; each feature degrades individually.
- The disassembler auto-detects Roblox's encoded opcodes (x227) vs plain Luau, and parses bytecode versions 3-14.
- Edit the GC blacklist at runtime: `getgenv().RCE.Modules["src/modules/GC.lua"].blacklist`.
- Use it on your own games / places you have permission to debug. Exploiting other people's experiences breaks Roblox's Terms of Use.
