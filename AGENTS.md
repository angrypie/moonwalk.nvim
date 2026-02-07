# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Moonwalk.nvim is a Neovim navigation plugin that uses a hybrid architecture combining Zig for performance-critical operations and Lua for Neovim integration. The plugin tracks and scores locations to enable smart navigation based on frecency algorithms.

## Architecture

The plugin uses a unique architecture:
- **Zig code** (plugin/*.zig) compiles to a dynamic library for performance-critical operations
- **Lua code** (lua/moonwalk/*.lua) handles Neovim integration and high-level logic
- **FFI Bridge** connects Lua to Zig through LuaJIT's FFI, loading the compiled dynamic library
- **C API** (api.c) defines Neovim's C API, which gets translated to Zig bindings

Key components:
- `plugin/main.zig` - Main Zig module exporting functions to Lua
- `plugin/nvim_lib.zig` - Neovim API bindings in Zig
- `plugin/shadow.zig` - Core suggestion/navigation logic
- `plugin/arena.zig` - Custom memory management
- `lua/moonwalk/init.lua` - Main Lua module managing extmarks and scoring
- `plugin/plugin.lua` - FFI bridge loading the Zig library

## Development Commands

### Building the Plugin

```bash
# In the plugin/ directory
make all
```

This runs two steps:
1. `make translate-c` - Translates C API definitions to Zig: `zig translate-c api.c > nvim_c_api.zig`
2. `make build-lib` - Compiles Zig to dynamic library: `zig build-lib ./main.zig -dynamic -fallow-shlib-undefined -fPIC -Denable-llvm=false`

### Testing

No formal test framework is configured. Test by:
1. Building the plugin with `make all`
2. Opening Neovim in the project directory
3. Using the test keybindings:
   - `<C-s>` - Triggers LLM code suggestions (calls `make_suggestions()`)
   - `<C-m>` - Test function (calls `process_array()`)

### Development Workflow

1. Modify Zig code in plugin/*.zig files
2. Run `make all` in plugin/ directory to rebuild
3. Restart Neovim or reload the plugin to test changes
4. The plugin loads the dynamic library from `./libmain.dylib` (macOS) or equivalent

## Important Notes

- The plugin requires Neovim 0.11+ (checked in init.lua)
- Dynamic library path is hardcoded in plugin.lua as `./libmain.dylib` - adjust for other platforms
- Generated files (nvim_c_api.zig, libmain.*) are gitignored
- Memory management uses a custom arena allocator in Zig for efficiency
- The plugin uses extmarks for tracking navigation points with scoring/frecency algorithms

## LLM Integration

The shadow.zig module implements LLM-powered code fixing and completion:
- `make_suggestions()` analyzes the visible code area (10 lines before/after cursor)
- Sends entire visible context to OpenAI API for analysis and fixing
- **Full area replacement**:
  - Analyzes the entire visible code area for syntax errors, incomplete statements, missing brackets
  - Returns a complete fixed version of the visible area
  - Intelligently parses markdown code blocks if LLM returns formatted responses
  - Removes line number prefixes (like "+1" or "  1") if present
  - Cursor remains at its current position after replacement
- Supports multiple LLM providers:
  - **Mistral** (default): Uses Codestral with predicted outputs for fastest responses
  - **OpenAI**: Uses GPT-4o with predicted outputs for high quality responses
- Provider selection via `LLM_PROVIDER` environment variable (defaults to Mistral)
- API keys:
  - OpenAI: Set `OPENAI_API_KEY` environment variable
  - Mistral: Set `MISTRAL_API_KEY` environment variable
- Both providers use predicted outputs optimization:
  - Sends the original code as prediction to speed up response time
  - Reduces latency by focusing computation on actual changes
  - Particularly efficient for small code fixes where most content remains unchanged

### API Functions Added
- `nvim_buf_set_lines()` - Sets/replaces lines in buffer (added to api.c and nvim_lib.zig)
- `nvim_win_set_cursor()` - Restores cursor position after code replacement
- Updated String type in api.c to match Neovim's actual API (struct with data and size)

### Usage
1. Set your API key:
   - For Mistral (default): `export MISTRAL_API_KEY="your-api-key-here"`
   - For OpenAI: `export OPENAI_API_KEY="your-api-key-here"`
2. (Optional) Choose provider: `export LLM_PROVIDER="openai"` (defaults to "mistral")
3. Build with `make all` in the plugin directory
4. Open a code file in Neovim
5. Position cursor in or near broken/incomplete code
6. Press `<C-s>` to analyze and fix the visible code area

### Example Use Cases
- Fix syntax errors in the visible area
- Complete incomplete function implementations
- Add missing closing brackets or parentheses
- Fix indentation issues
- Complete partial statements or expressions