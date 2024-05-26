# This is a Work In Progress!
And as of yet, not well tested.

## RoundHandler
A Roblox round engine, initially developed for [Those You Trust](https://www.roblox.com/games/2848381272). Provides a simple way to create role-based gamemodes, with support for advanced functions.

### Goal
It should be possible to recreate Trouble In Terrorist Town, from GMod, without modification to RoundHandler itself.
Thus, map loading should, for example, integrate Props, but there is no requirement for Prop-kills to be possible.

### Build
[Rojo](https://github.com/rojo-rbx/rojo) must be installed for build to work.
To build, enter the directory and run
```bash
rojo build -o RoundHandler.rbxm
```
This will build the src folder into RoundHandler.rbxm.

[License](https://github.com/Skekdog/RoundHandler/blob/master/LICENSE)