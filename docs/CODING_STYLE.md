# Coding Style

Derived from the public GitHub repos `nikolashuang/Godspire`, `Overtake`, `Journey-Afar` and `Project-GP`. All four are Rojo + Luau Roblox projects, so these are Luau/Roblox conventions, not cross-language ones. Overtake is the most developed codebase and is weighted most heavily.

## Project Layout (Rojo)

All repos use the default Rojo mapping:

| Folder        | Maps to                                  |
|---------------|------------------------------------------|
| `src/shared`  | `ReplicatedStorage.Shared`               |
| `src/server`  | `ServerScriptService`                    |
| `src/client`  | `StarterPlayer.StarterPlayerScripts`     |

Entry points are a single `main.server.luau` / `main.client.luau` that wire modules together. Systems are grouped into folders by domain:

```
src/server/PlayerProfile/ProfileService.luau
src/server/Services/CombatService.luau
src/client/Controllers/InputController.luau
src/shared/Parkour/ParkourConfig.luau
src/shared/Character/CharacterClass.luau
```

- **Client modules** are `XController` (`InputController`, `AnimationController`, `UIController`).
- **Server modules** are `XService` (`ProfileService`, `CombatService`).
- **Class modules** are `XClass` (`CharacterClass`, `HeroClass`).
- **Data/tuning modules** are `XConfig` (`ParkourConfig`, `HeroConfig`, `MovementConfig`).

## Naming

| Thing | Convention | Example |
|---|---|---|
| Modules, classes, local module refs | PascalCase | `local ParkourConfig = require(...)` |
| Functions / methods | PascalCase | `CharacterClass:BindCharacter`, `ProfileService.LoadProfile` |
| Instance fields on `self` | Mostly PascalCase | `self.MomentumUnit`, `self.RootPart`, `self.LastVault` |
| Boolean state flags | `isX` / `canX` camelCase | `self.isSliding`, `self.isWallRunning` |
| Config constants | UPPER_SNAKE inside nested tables | `VaultConfig.VAULT_CD`, `MomentumConfig.MAX_MOMENTUM` |
| Local variables | camelCase | `local timingWindow`, `local plrCharacter` |
| Timestamps | `LastX` storing `time()` | `self.LastVault = time()` |
| Guard checks | `CanX()` returning bool | `CharacterClass:CanVault()` |
| Client→server wrappers | `AttemptX()` | `ParkourController.AttemptVault()` |

Service aliases vary across repos (`RepStorage`, `ReplicatedStorage`, `RPS`). **For Shotgun Chess, use the full service name** (`ReplicatedStorage`, `UserInputService`) for consistency.

## Classes

Classes use plain metatables. `new` sets every field up front (often `nil` placeholders), grouped by concern and separated by blank lines:

```lua
local CharacterClass = {}

CharacterClass.__index = CharacterClass

function CharacterClass.new(player, profile)
    local self = setmetatable({}, CharacterClass)

    self.Player = player
    self.Profile = profile

    self.Character = nil
    self.Humanoid = nil
    self.RootPart = nil

    self.Staggered = false
    self.LastDodge = 0

    return self
end
```

Construction and instance binding are split: `new()` builds state, and `BindCharacter(character)` attaches the Roblox instances. This lets the object survive respawns (`player.CharacterAdded` re-binds).

**Composition** is used for variant behaviour. In Godspire, `HeroClass` looks up a per-hero module by name and stores it as a component:

```lua
local heroModule = HeroComponentFinder:WaitForChild(self.HeroName)
local HeroComponentRequest = require(heroModule)
self.HeroComponent = HeroComponentRequest.new(self, self.Stats)
```

Shotgun classes (Necro/Spark/WindCharge/Forge) map naturally onto this pattern.

## Stateless Modules

Controllers and services are plain tables with dot-functions, not classes. Module-level locals hold state, and `Init` uses a guard:

```lua
local InputController = {}

local init = false
function InputController.Init()
    if init then return end
    init = true
    ...
end

return InputController
```

## Config Modules

Tuning numbers live in config tables, never inline in logic. Nested by system, with sub-tables aliased at the top of the consumer:

```lua
local ParkourConfig = require(ReplicatedStorage.Shared.Parkour.ParkourConfig)
local VaultConfig = ParkourConfig.Vault
local MomentumConfig = ParkourConfig.Momentum
```

Per-entity data is keyed by name (`HeroConfig.Polvern = { MaxHP = 500, ... }`).

## Control Flow

Heavy use of **early-return guard clauses**, one condition per line, `then return end` on the same line:

```lua
function CharacterClass:CanVault()
    if self.traversalType ~= "Vault" and self.traversalType ~= "Hurdle" then return false end
    if self.Staggered then return false end
    if not self:isGrounded() then return false end
    if time() - self.LastVault < VaultConfig.VAULT_CD then return false end

    return true
end
```

Input and remote dispatch use flat `if / elseif` chains on a string action name rather than lookup tables:

```lua
mRemote.OnServerEvent:Connect(function(player, action, direction, behavior)
    local character = Characters[player]
    if not character then return end

    if action == "Sprint" then
        ...
    elseif action == "Dodge" then
        ...
    end
end)
```

Cooldowns compare `time()` against stored timestamps instead of using `task.wait` loops.

## Networking

- One RemoteEvent per system (`ParkourRemote`, `MovementRemote`, `CombatEvent`), with the action passed as the first string argument.
- Remotes live in a `Remotes` folder in ReplicatedStorage (Overtake, Journey Afar).
- The server keeps a `Characters[player]` lookup table populated in `PlayerAdded` and cleared in `PlayerRemoving`.
- Server handlers validate before acting: look up the player's object, check ownership and alive state, then dispatch. This is the pattern from `CombatService.HandleRequest`.

## Formatting

- 4-space indentation (a few older files and Project-GP use tabs).
- `game:GetService` calls first, then `require`s, then module-level constants and state, then the module table.
- Blank lines between logical groups. Trailing blank lines before `return Module` are common.
- No type annotations.

## Comments

Sparse. Comments are used for:
- Section dividers in long files: `--VAULTING--`, `--HELPER ANIMATION FUNCTIONS--`, or block banners:
  ```lua
  --[[----------------------------------------------------------------------------------------

  COMBAT MECHANICS

  ]]------------------------------------------------------------------------------------------
  ```
- Short clarifications on config values (`-- Neutral`, `--Preallocated Stat Points`).

No doc comments on functions.

## Overall Preferences

- Simple and direct over abstract: no frameworks, no dependency-injection containers, no signal libraries.
- OOP only for stateful entities (characters, heroes); everything else is a plain module.
- Large single-class files are tolerated for one entity (Overtake's `CharacterClass` is ~780 lines), but separate systems stay in separate modules.
