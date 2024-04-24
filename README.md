# This is a Work In Progress!
And as of yet, not actually tested.

## Round Handler
A Roblox round engine, initially developed for [Those You Trust](https://www.roblox.com/games/2848381272). Provides a simple way to create role-based gamemodes, with support for advanced functions.

src/Adapters.lua contains implementation functions that should be changed for your specific needs.
example_implementation contains example implementation of the RoundHandler - the game script itself and gamemodes.

### Build
[Lune](https://github.com/lune-org/lune) must be installed for build to work.
To build, enter the directory and run
```bash
lune run build
```
This will build the src and examples folders into RoundHandler.rbxm.

[License](https://github.com/Skekdog/Round-Handler/blob/master/LICENSE)