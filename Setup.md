# NPC + Base Capture/Income/Mutation/Level System Setup

This document explains the current server-authoritative system and the new **owned NPC level-up** flow.

---

## What changed in this revision

This update extends the existing slot/owned architecture (it does not replace it) with a per-owned-brainrot level system.

### New capabilities

1. Per-slot owned NPC level state (`Level`) with default Level 1.
2. Level-based income scaling for owned NPCs: `* 1.10` per level.
3. Level-based upgrade cost scaling: `* 1.50` per level.
4. Per-slot `UpgradePart` UI integration:
   - `UpgradePart > UpgradeGui > Button > Cost`
   - `UpgradePart > UpgradeGui > Button > LevelChange`
5. Server-authoritative upgrade request validation.
6. Owned billboard level text updates (`Lv.X`) and generation updates in-sync with actual production.
7. Save/load persistence now includes `Level` per slot occupant.
8. Mutation + level income stacking now centralized (single source of truth math helper).

---

## Files added

- `ReplicatedStorage/NPCSystem/Config/OwnedNPCLevelConfig.lua`
- `ReplicatedStorage/NPCSystem/Shared/OwnedNPCLevelMath.lua`
- `ReplicatedStorage/NPCSystem/Shared/CompactNumberFormatter.lua`
- `StarterPlayer/StarterPlayerScripts/NPCUpgradeButtons.client.lua`

## Files updated

- `ReplicatedStorage/NPCSystem/Config/NPCDefinitions.lua`
- `ReplicatedStorage/NPCSystem/Config/NPCRegistry.lua`
- `ReplicatedStorage/NPCSystem/Shared/NPCTypes.lua`
- `ServerScriptService/NPCSystem/Services/BaseSlotService.lua`
- `ServerScriptService/NPCSystem/Services/BaseIncomeService.lua`
- `ServerScriptService/NPCSystem/Services/DataService.lua`
- `ServerScriptService/NPCSystem/Services/NPCStateService.lua`
- `StarterPlayer/StarterPlayerScripts/NPCClientFeedback.client.lua`

---

## Core level rules

- New captured/owned NPCs start at `Level = 1`.
- Level is tracked per slot occupant and restored from save.
- Deleting an owned NPC removes its slot state (including level).
- Replacing slot occupant with a different NPC resets to that NPC's own state (new capture => level 1, restore => saved level).

---

## Centralized math (single source of truth)

All owned level math is centralized in `OwnedNPCLevelMath`.

### Income formula

```
effectiveIncome = mutatedBaseIncome * (1.10 ^ (level - 1))
```

Where:
- `mutatedBaseIncome` comes from mutation multipliers (`MutationRegistry.ApplyMultipliers`)
- level multiplier is from `OwnedNPCLevelConfig.LevelIncomeMultiplier` (default `1.10`)

### Upgrade cost formula

```
upgradeCost = baseUpgradeCost * (1.50 ^ (level - 1))
```

Where:
- `baseUpgradeCost` is configured per NPC definition (`NPCDefinitions.*.BaseUpgradeCost`)
- multiplier is from `OwnedNPCLevelConfig.UpgradeCostMultiplier` (default `1.50`)

### Max level rule

- Owned brainrots have a hard maximum level of `100`.
- Any saved/restored or runtime level above `100` is clamped back to `100` safely.
- Level `99` can upgrade to `100`, but level `100` cannot upgrade any further.

### Display helpers

- Level text: `Lv.X`
- Level change text: `Level X > Level Y` (or `Level 100 > MAX` at cap)
- Currency format uses shared `FormatCurrency`

---

## NPC definition requirements

Each NPC definition now requires:

- `BaseUpgradeCost` (number, > 0)

Validation is enforced in `NPCRegistry`.

---

## UpgradePart hierarchy and binding

Per slot, the system resolves this exact structure:

```
Slot
  UpgradePart (BasePart)
    UpgradeGui (SurfaceGui)
      Button (TextButton)
        Cost (TextLabel)
        LevelChange (TextLabel)
```

No alternate hierarchy names are used.

### How per-slot UI is managed

`BaseSlotService` updates each slot independently:

- **When occupied**:
  - `Cost` shows current cost to buy the next level
  - `LevelChange` shows `Level X > Level Y` while below cap and `Level 100 > MAX` at cap
- **When empty**:
  - `Cost` resets to `$0`
  - `LevelChange` resets to `Level -`
  - stale text from old occupant is removed

Because updates are slot-scoped, Slot A and Slot B always reflect their own occupant state.

---

## Upgrade request flow (server authoritative)

Client script (`NPCUpgradeButtons.client.lua`) only sends a request with `SlotName`.
Server (`BaseSlotService`) decides final outcome.

### Server validations

1. Payload shape valid.
2. Slot exists in requesting player's assigned base.
3. Requester owns that base.
4. Slot currently has a valid occupant and slot state.
5. Definition exists.
6. Player has enough money for current upgrade cost.

### On success

1. Deduct money (via `DataService.SetMoney` when available).
2. Increment level (`+1`).
3. Recompute effective income using mutation + level formula.
4. Update slot income rate (`BaseIncomeService.UpdateIncomeRate`) without resetting loop ownership logic.
5. Refresh owned billboard texts:
   - Generation
   - Mutation
   - Level (`Lv.X`)
6. Refresh slot `UpgradePart` cost and level-change text.
7. Mark slot data changed for persistence callback.

### On failure

- No level change.
- No money removal.
- No invalid state mutation.

---

## Owned billboard updates

Owned billboard now stays synchronized with actual state:

- `Generation` uses effective runtime income with rebirth applied and renders as:
  - `$500/s (x1)`
  - `$1.2K/s (x1.5)`
  - `$10K/s (x2)`
- the value before `(xN)` is the real per-second amount currently generated server-side for that owned brainrot.
- `Mutation` shows mutation name, fallback `Normal`.
- `Level` shows `Lv.X`.

If `Level` label is missing from the template, gameplay still works; level text simply won't render visually.

---

## Persistence changes

Slots now persist as objects (legacy string saves are still accepted):

```lua
{
  Money = "1234",
  Slots = {
    ["Slot1"] = {
      NpcId = "Slime",
      MutationId = "Gold", -- optional
      Level = 3,            -- defaults to 1 if absent
    }
  }
}
```

### Backward compatibility

- Old slot saves like `Slots["Slot1"] = "Slime"` still load.
- Missing `Level` restores as `1`.

---

## MoneyIndicator high-value display fix (beyond `9qi`)

### What was wrong

The money backend was already migrated to large-number string state, but the MoneyIndicator chain could still render stale/limited values during client-side timing windows.
In practice this made the indicator appear to plateau around `9qi` in some sessions even when backend money kept increasing.

### Correct display chain now

1. **Authoritative source:** `DataService` money string (`session.Data.Money`).
2. **Replication bridge:** `player:SetAttribute("MoneyString", <digit-string>)` on every money update.
3. **Direct backend fetch fallback:** new `RemoteFunction` `MoneySnapshot` returns `DataService.GetMoneyString(player)`.
4. **Client binding:** `NPCClientFeedback` reads `MoneyString`, and if it is missing/zero during late-load race windows, it invokes `MoneySnapshot` once to hydrate from authoritative backend.
5. **Formatting:** `CompactNumberFormatter.FormatCurrency` consumes the digit-string directly (no lossy `tonumber()` conversion).
6. **Final UI assignment:** `MoneyIndicator > MoneyFrame > MoneyLabel`.Text.

### Why it no longer caps at `9qi`

- MoneyIndicator no longer depends on leaderstats numeric display state as an authority source.
- The client formatting path keeps money as a string all the way into compact formatting.
- Large values therefore bypass Roblox number precision limits that typically show up around `qi` ranges.
- Formatter overflow behavior now falls back to scientific notation when suffix table range is exceeded, rather than appearing capped.

### Safety/edge cases handled

- UI loads before data: snapshot fallback hydrates from server backend.
- Data loads before UI: attribute change listener and initial bind render latest value.
- Duplicate listeners: existing money listener is disconnected before rebinding.
- Nil/invalid values: both client and server sanitize to non-negative digit strings.

---

## Floor-based slot resolution (Floor1 active)

`BaseSlotService` now resolves usable slots through a deterministic floor-aware pipeline.

### Current active floor behavior

- The system now has a floor concept for slot discovery.
- **Only `Floor1` is active right now**.
- Active slots are gathered from active Floor1 container, supporting either:
  - `Bases/<Base>/Floor1/Slots` (preferred), or
  - legacy `Bases/<Base>/Slots/Floor1`.
- Inside the floor, slots are sorted by numeric slot suffix (`Slot1`, `Slot2`, ... `Slot10`) and then by name as fallback.

### Deterministic placement order

When sending/capturing a brainrot into the base, placement is deterministic:

1. Try `Floor1/Slot1`
2. If occupied, try `Floor1/Slot2`
3. Continue ascending until `Floor1/Slot10` (or highest existing slot)
4. If no free slot exists, existing full-base behavior is preserved (`NoFreeSlots` flow)

This guarantees lower-index free slots are always filled first (for example, if `Slot3` becomes free later, the next placement targets `Slot3` before higher slots).

### Missing floor / compatibility fallback

- If `Floor1` is missing, service logs a warning and falls back to root slot parts under `Slots` to avoid breaking older base layouts.
- Non-slot objects inside floor folders are ignored safely.
- Existing save format remains compatible (slot entries keyed by slot name still load as before).

### Future floor expansion design

- Floor selection is centralized through a helper (`getFloorOrderForNow`) that currently returns `{1}`.
- To unlock more floors later, extend that helper to return `{1,2,...}` based on progression/unlock data.
- Slot ordering already composes floors first, then slot indices, so no major placement refactor is needed for `Floor2+`.

## Base upgrade progression

Players now have a separate base-upgrade progression that unlocks extra slot capacity beyond the default Floor1 state.

### Starting state
- Floor1 is the default base floor.
- Floor1 starts with 10 usable slots (`Slot1` to `Slot10`).
- Base upgrade count starts at `0`.

### Upgrade progression rule
- Each successful base upgrade unlocks exactly one new usable slot progression step.
- Progress is centralized in `ReplicatedStorage/NPCSystem/Config/BaseUpgradeConfig.lua` and `ReplicatedStorage/NPCSystem/Shared/BaseUpgradeProgression.lua`.
- `BaseUpgradeProgression.GetUpgradeState(upgradeCount)` is the single authoritative mapping from upgrade count to required floors, unlocked slots, and total usable slot capacity, and both live upgrades and reconstruction use that same state.
- Floor unlock order is strict and deterministic:
  1. Floor2 unlocks first and starts with only `Slot11` usable.
  2. Later upgrades unlock `Slot12`, `Slot13`, and so on in order.
  3. Unlocking a new floor and enabling its first slot still counts as just **one** upgrade step.
  4. After Floor2's progression is complete, Floor3 unlocks and starts with exactly one usable slot.
  5. Later upgrades unlock the remaining Floor3 slots in order.
- `SlotCount` on the base-upgrade button shows `currentUpgrades/maxUpgrades` (for example `0/20`).

### Floor cloning source
- Additional floors are cloned from `ReplicatedStorage/Floors/<BaseLayout>/...`.
- `ServerScriptService/NPCSystem/Services/BaseUpgradeService.lua` resolves the player's assigned base layout folder and clones only the floors required by the saved/current upgrade count.
- Newly cloned floors are pre-locked before being parented into the live base so a floor unlock never briefly exposes multiple future slots at once.
- When a player leaves and releases a base, dynamically added floors are removed so the physical base returns to the default Floor1-only state for the next owner.

### Locked vs unlocked slots
- Slots are only considered usable when the server marks them unlocked with the base-upgrade slot attribute.
- Locked future slots may physically exist inside a cloned floor model, but they do **not** count as capacity, do **not** show as active usable slots, and are filtered out of `BaseSlotService` slot resolution.
- Server slot resolution now only accepts uniquely numbered `Slot%d` parts per floor/root container, which prevents duplicate slot instances or non-slot parts from inflating capacity or causing two-at-a-time progression.
- When upgraded floors are cloned, their unlocked slots are rebound into the same collect / upgrade / prompt flows as Floor1 via descendant-based slot discovery, while locked future slots remain inactive.
- This means base-full checks, free-slot checks, placement, swap, restore, and prompt binding only operate on unlocked slots.

### Persistence and reconstruction
- Base upgrade count is saved per player alongside money and slot state.
- On join/base assignment, the server restores base upgrade count first, reconstructs Floor2/Floor3 as needed, activates the correct unlocked slots, and only then restores saved slot occupants.
- This guarantees slot restore cannot place owned NPCs into floors/slots that should still be locked.
- For temporary development/testing, the owner can use the Studio-only chat command `/resetbaseupgrades` to reset only their base-upgrade progression back to `0`, rebuild the assigned base to Floor1-only, and keep unrelated saved systems intact where possible.

### Base upgrade button UI and feedback
- The base upgrade button is read from `BaseUpgrade > GUIPart > SurfaceGui > Button`.
- `Cost` shows the current configured price, or `MAX` when the base is fully upgraded.
- Upgrade prices are centralized and now scale multiplicatively by `x7` each step, starting from the configured base cost.
- The server is the only authority that can purchase a base upgrade, and it now applies a per-player purchase-in-progress guard plus a short debounce so one interaction cannot accidentally process two upgrade purchases.
- `SlotCount` shows current progress using `current/max`.
- Successful upgrades spend money, rebuild the base progression, update the UI, and play `ClientAssets/UpgradeSuccessSFX`.
- Failed not-enough-money upgrades show `No tienes suficiente dinero!` and play `ClientAssets/UpgradeInsufficientSFX`.
- Failed maxed upgrades show `Alcanzaste la mejora maxima!` and also play `ClientAssets/UpgradeInsufficientSFX`.
- `BaseUpgrade > GUIPart > AlertGui` is handled client-side so only the base owner sees it. It enables only when that owner currently has enough money for the next upgrade, and it disables when the base is unassigned, maxed, or unaffordable.

## Slot lifecycle behavior

### Capture into slot

- New capture starts Level 1.
- Slot state is created.
- Income starts at effective Level 1 income.
- Billboard + UpgradePart initialize immediately.
- Slotted model orientation is rebuilt from the slot's forward direction using the brainrot's `HumanoidRootPart` as the facing anchor, so every brainrot's front follows the front of the slot consistently even when the model pivot/HRP are offset.

### Delete from slot

- Slot occupancy removed.
- Slot level state removed.
- Income loop stopped for that slot.
- UpgradePart reset to empty defaults.

### Restore from save

- Definition + mutation + level restored.
- Effective income recomputed from deterministic formulas.
- Billboard and UpgradePart synced to restored state.
- Restored placements reuse the same HRP-driven slot-facing placement path, so loaded brainrots keep the same consistent slot-forward orientation as live placements and swaps.

### Reuse same slot with new NPC

- Old state is cleared on delete.
- New occupant receives its own new state.
- UI updates to the new occupant only.

---

## Configuration knobs

### `OwnedNPCLevelConfig`

- `LevelIncomeMultiplier` (default 1.10)
- `UpgradeCostMultiplier` (default 1.50)
- `DefaultLevel` (default 1)
- `MaxLevel` (default 100)
- Upgrade UI object names
- Empty-state text values
- Upgrade request remote event name

### `NPCDefinitions`

Per NPC:
- `BaseUpgradeCost`
- `CapturableLifetimeSeconds`

---

## Edge-case handling included

- Empty slot upgrade requests are ignored safely.
- Non-owner requests are rejected.
- Missing/invalid definitions are rejected.
- Stale UI button presses after deletion do nothing.
- Missing level in saves defaults to 1.
- Displayed generation and actual generated money are both derived from the same helper.

---

## Notes / assumptions

- Slots are marker-driven and now resolved through deterministic floor+slot numeric ordering.
- Existing systems remain intact: base assignment, occupancy, capture prompt flow, delete, collection, mutation, persistence.
- Upgrade button click capture is client-side input, but all upgrade authority is server-side.


---

## Global compact number formatting (very large values)

All visible money/income/cost amounts now use one centralized formatter:

- `ReplicatedStorage/NPCSystem/Shared/CompactNumberFormatter.lua`

### Why

This is a global display-only refactor so extremely large values stay readable and consistent across UI.
Internal game math, save data, income calculations, and upgrade calculations are unchanged.

### Suffix progression

The formatter supports a long 1000-step suffix chain, including:

`"", "k", "m", "b", "t", "qa", "qi", "sx", "sp", "oc", "no", "dc", "ud", "dd", "td", "qad", "qid", "sxd", "spd", "ocd", "nod", "vg", ... "noqag"`

It is easy to expand by appending more entries to the suffix table.

### Rounding style

- `< 1000`: rounded integer (no suffix)
- `>= 1000`: compact suffix format
  - up to 2 decimals for small leading values
  - 1 decimal for medium leading values
  - 0 decimals for large leading values
- trailing zeroes are trimmed (`1.0k` -> `1k`)

### Overflow / very large values

If a value exceeds the configured suffix list range, formatting safely clamps to the highest available suffix instead of crashing.

### Systems now using shared formatter

- player money label (`NPCClientFeedback`)
- slot collect amounts (`BaseIncomeService`)
- world NPC generation text (`NPCStateService`)
- owned NPC generation text (`BaseSlotService`)
- upgrade cost text (`OwnedNPCLevelMath` via `FormatCurrency`)
- insufficient funds label cost text (`NPCUpgradeButtons`)

### Wrapper behavior

Wrappers are preserved while number body is compacted:

- currency uses prefix (e.g. `$1.25m`)
- generation uses `/s` (e.g. `1.2m/s`)

---

## Owned brainrot grab/carry/place/swap system (base slots only)

This revision extends the **existing owned slot system** (it does not replace it) with server-authoritative movement of already-captured brainrots between slots.

### Scope

- Applies **only** to owned/captured NPCs inside player bases.
- Not used for world NPCs.
- No stealing logic is included in this change.

---

### What changed

#### Config

`BaseConfig.OwnedCarry` was added to centralize prompt/carry behavior:

- `GrabPromptName`, `GrabActionText`, `GrabObjectText`, `GrabKeyboardKeyCode`
- `GrabMaxActivationDistance` (default `15`)
- `GrabRequiresLineOfSight`
- `GrabUIOffset` (configured above delete prompt)
- `PlacePromptName`, `PlaceActionText`, `PlaceObjectText`, `PlaceKeyboardKeyCode`
- `PlaceMaxActivationDistance` (default `15`)
- `PlaceRequiresLineOfSight`
- `PlaceUIOffset`
- `DeleteUIOffsetWhenGrabEnabled` (configured below grab prompt)
- `CarryForwardDistance`, `CarryUpOffset`
- `EnablePlacePromptOnlyWhileCarrying`

#### Server behavior (`BaseSlotService`)

Added modular carry/move internals integrated into existing occupancy + state + income + persistence flow:

- prompt binders for grab/place
- carry state tracking per player (one carried model max)
- slot payload extraction + slot clear + slot reassign helpers
- swap logic preserving per-brainrot state
- safe carry recovery on reset/leave
- slot prompt enable/disable while carrying (per base)

---

### Prompt hierarchy/order

For slotted owned NPCs:

- **Grab prompt** (`E`) is attached with `OwnedCarry.GrabUIOffset` (above).
- **Delete prompt** (`X`) remains active and uses `OwnedCarry.DeleteUIOffsetWhenGrabEnabled` (below).

For slots:

- **Place prompt** (`E`) is attached to each slot.
- Can be globally hidden unless carrying (`EnablePlacePromptOnlyWhileCarrying = true`).

This keeps a predictable “E above / X below” presentation instead of overlapping prompts.

---

### Grab flow

1. Player triggers grab prompt on owned slotted NPC.
2. Server validates:
   - player is base owner,
   - player is not already carrying,
   - NPC is still the current occupant of that slot.
3. Server extracts the exact slot payload (`DefinitionId`, `MutationId`, `Level`, model reference).
4. Old slot is immediately cleared in system state:
   - occupancy cleared,
   - slot state cleared,
   - income stopped,
   - upgrade empty state restored,
   - persistence callback notified (`slot=nil`).
5. NPC enters carry mode and follows in front of player each heartbeat.

Important: this is the same NPC instance; no recreate/clone path is used for moving.

---

### Carry behavior details

- Carried model is snapped immediately to a strict front-facing carry target derived from the player `HumanoidRootPart` when grabbed.
- The safe front offset uses the configured `CarryForwardDistance` plus half of the carried model bounding-box depth, with `CarryUpOffset` still applied vertically, so the carried assembly stays clearly in front of the player without intersecting the character.
- Carry motion remains fully decoupled from the brainrot’s internal assembly: carry helpers stay external in `Workspace.NPCCarryHelpers`, while the full anchored NPC model is moved as a whole unit with `Model:PivotTo(...)`.
- The carry-motion change was limited strictly to keeping the external carry helper attached to the carrier’s current `HumanoidRootPart` transform on every carry update, and then driving the full NPC from that attached front helper so the brainrot stays locked in front instead of behaving like a follower.
- Internal brainrot welds, attachments, Motor6Ds, cleanup rules, and other legitimate assembly-preservation logic were intentionally left untouched by this carry fix.
- `Base`, `EPart`, and `XPart` remain protected permanent parts of the brainrot assembly and must stay attached during carry, drop, redeem, and placement.
- The front-carry offset still uses the configured `CarryForwardDistance` plus half of the carried model bounding-box depth, with `CarryUpOffset` applied vertically for safe separation from the player.
- On placement, the protected permanent parts `Base`, `EPart`, and `XPart` are explicitly restored to their captured normal relative alignment on the NPC before slot placement completes, so they return to the correct attached position every time without broad cleanup or joint destruction.
- Temporary carry helpers remain isolated outside the NPC model, and cleanup removes only those explicit carry-only helpers.
- This prevents the old regression loop by separating responsibilities: carry updates only move the whole NPC to the front-carry target, while placement restores the protected permanent part alignment back to the NPC’s normal arrangement.
- This change is limited to carry motion plus protected-part post-placement restoration; it preserves the current assembly protection, placement flow, billboard behavior, and redeem flow.
- One carried NPC per player is enforced server-side.
- Carrying disables idle animation until slotted again.

---

### Place into empty slot

When placing onto an empty slot:

- carried payload is assigned to target slot,
- same model and state are reused,
- mutation/level remain unchanged,
- effective income is recomputed from existing state and resumed on target slot,
- billboard/upgrade/delete+grab prompts are rebound,
- slot changed callback fires for persistence.

---

### Place into occupied slot (swap)

When placing onto an occupied slot:

1. carried payload becomes occupant of target slot,
2. previous target occupant payload is moved into carried NPC’s previous source slot,
3. each payload keeps its own `DefinitionId`, `MutationId`, and `Level`.

No delete/recreate swap hack is used; state follows the brainrot payload.

Both slots are refreshed through existing slot systems (income/UI/persistence callbacks).

---

### Slot-state and persistence integrity

Persistence remains driven by existing slot changed callbacks into `DataService`.

Move/swap operations use the same notify path already used by capture/delete/upgrade:

- clearing source slot notifies nil,
- placing target slot notifies new payload,
- swap updates both slot entries.

Result: leaving/rejoining preserves moved/swapped positions and preserved mutation/level.

---

### Reset / leave / safety behavior

To prevent carry-loss/duplication edge cases:

- on character death/removal (`Humanoid.Died` / `CharacterRemoving`), carried NPC is safely re-slotted immediately,
- on respawn (`CharacterAdded`), carry safety rebinds for the next character,
- on `PlayerRemoving`, carried NPC is safely re-slotted before normal cleanup,
- if original source slot is unavailable, first free slot is used,
- if no safe slot exists, fail-safe destroy is used with warning (prevents dupes).

---

### Existing systems compatibility

The carry/move/swap path is wired into the existing owned-slot architecture and keeps these working:

- ownership checks (`BaseService.IsOwner`)
- slot occupancy map
- per-slot income loops (`BaseIncomeService`)
- collect part amount UI reset/resume
- upgrade part occupied/empty states
- delete prompt behavior
- owned billboard mutation/level/generation text
- persistence callback pipeline

---

### Prototype assumptions / limitations

- Carry visual is server-driven anchored follow (simple, stable prototype).
- Place prompts are slot-level prompts with server validation; ownership is enforced server-side.
- This change intentionally excludes any cross-player steal mechanics.

---

## Rebinding bugfixes for runtime move/swap (no rejoin required)

This patch fixes the broken runtime behavior where moved/swapped brainrots could stop producing or end up stacked/incorrectly bound.

### What was broken

- Move to empty slot could visually move the model but leave slot-linked systems in a partially rebound state.
- Occupied-slot place could drift into a bad swap state where both models ended up effectively tied to one slot lifecycle path.
- Prompt instances could duplicate because old prompts were not always found recursively before rebinding.

### What changed in code

`BaseSlotService` now uses clearer central lifecycle paths for slot movement:

- `detachPayloadFromSlot(...)`
  - extracts exact occupant payload (`Model`, `DefinitionId`, `MutationId`, `Level`)
  - clears occupancy/state/income/UI for that slot
  - notifies persistence callbacks for empty state when required
- `placePayloadIntoSlot(...)`
  - performs full slot claim/rebind path (position, state, billboard, prompts, upgrade UI, income start, persistence notify)
- `handleCarryPlaceRequest(...)`
  - uses deterministic empty-place path
  - uses deterministic swap path with rollback safety if any attach step fails
  - ensures both slots end in valid single-occupant states

### Swap behavior now

For A(from slot A) placed on occupied slot B:

1. detach payload currently in B,
2. attach carried A to B,
3. attach detached B payload to A,
4. if any step fails, rollback attempts restore consistent slot occupancy.

This prevents double-binding/stacking and ensures both slots remain operational.

### Rebinding guarantees after move/swap

After successful place/swap, both affected slots are rebound immediately:

- occupancy map
- slot state map
- per-slot income loop
- collect part amount UI
- upgrade part state
- owned billboard
- grab/delete prompts
- slot-changed persistence callback path

No rejoin is needed for production/UI to resume.

### Prompt rebinding fix

Prompt cleanup now searches recursively before creating replacement prompt instances:

- grab prompt
- delete prompt

This prevents stale/duplicate prompt instances after repeated moves/swaps.

### Persistence correctness

Because move/swap continues using existing slot-changed callback notifications:

- source/target slot save entries are updated during runtime move/swap,
- mutation/level remain attached to their original brainrot payload,
- save data and runtime state stay aligned.

### Hotfix: nil-call during runtime place/swap

A runtime crash was fixed where `placePayloadIntoSlot` could call `attachDeletePrompt` before a local binding existed in file scope order, producing `attempt to call a nil value` in Studio logs during place/swap.

Fix applied:
- added explicit forward declaration for `attachDeletePrompt`
- converted its later declaration to assignment form so earlier lifecycle helpers resolve the correct local function

This prevents mid-swap aborts that could leave slot state visually/behaviorally inconsistent.

---

## Centralized final slot placement flow

The final owned-brainrot placement path is now centralized in `BaseSlotService` so capture, place, swap, safe carry recovery, and save restore all finish through the same authoritative slot-placement rule.

### Real root cause of the offset bug

The bad placement after grab/place was not caused by one missing Y offset alone.

The full root cause was a combination of **duplicate placement**, **live-pose placement metadata**, and one later regression from **over-aggressive cleanup**. The safest policy now is to treat each brainrot model’s internal assembly as untouchable.

1. Runtime place/swap previously scheduled extra deferred “resnap” placements after the main place call.
2. Final placement was also being derived from the model’s **current** `GetBoundingBox()` / pivot-to-box transform instead of from one stable slot-placement reference captured in the model’s neutral cloned pose.
3. Because idle animation and carry/release could leave the live bounding box in a slightly different pose, each later placement could recompute a different standing offset from an already-shifted runtime state.
4. A later cleanup pass became too broad and risked removing legitimate assembled-model joints/constraints while trying to clean carry leftovers, which could make visual parts or billboard anchor parts detach even though the main rig pivoted correctly.
5. The grab-time detach bug was traced to carry-time physics on the assembled model: when grab changed the model into a carried physics state, permanent parts like `Base`, `EPart`, and `XPart` could simulate independently and fall away from the rig.
6. The safest fix is to keep those permanent parts protected by leaving the carried brainrot anchored and moving the whole model as one unit during grab/carry.
7. Carry helpers remain isolated outside the brainrot model in `Workspace.NPCCarryHelpers`, so the carry/place pipeline never needs to inspect or clean joint-like descendants inside the NPC model.

That is why the issue could look cumulative over repeated grab/place cycles:

- a later placement could reuse an already-shifted live bounding box,
- another placement pass could run after the main one,
- the effective Y correction could be reapplied from different runtime poses over time.

Symptoms from this bug family were:

- occasional upward placement,
- occasional sideways drift,
- unstable repeated grab -> place cycles,
- “sometimes correct / sometimes wrong” placement depending on current pose timing,
- detached visual parts/billboards if cleanup removed real assembly joints instead of only carry helpers.

### Authoritative placement path now

Final slot placement now goes through one path only:

- `placeDefinitionIntoSlot(...)`
  - used for first capture and save restore
  - ends by calling `finalizeSlotPlacement(model, slot)`
- `placePayloadIntoSlot(...)`
  - used for runtime place, swap, and safe carry recovery
  - ends by calling the same `finalizeSlotPlacement(model, slot)`
- `finalizeSlotPlacement(...)`
  - restores slotted physics,
  - increments a placement sequence for debug tracing,
  - clears temporary carry/external movement artifacts,
  - calls `placeModelOnSlot(...)` exactly once,
  - optionally performs a delayed debug-only drift check when `OwnedNPCLevelConfig.DebugLogs` is enabled.

No deferred post-place resnap calls remain in the runtime move/swap path.

### Slot-facing orientation rule

- Final slot orientation is authoritative from the slot part itself.
- Capture placement, manual place, swap, safe carry recovery, and save restore all finish through `finalizeSlotPlacement(...)`, so each of those flows now forces the brainrot to face the slot part's front direction.
- Previous world rotation from carrying or earlier slot positions is not reused as the final slot rotation.

### How final position is computed

`placeModelOnSlot(model, slotPart)` now computes the final transform deterministically like this:

1. Resolve the placement reference part (`slot.Spawn` if present, otherwise the slot part itself).
2. Project that reference point onto the slot part’s actual top surface using the slot’s own `CFrame` and size.
3. Force the final facing to come from the slot part’s own orientation, so every brainrot in that slot faces the slot front direction instead of preserving any previous runtime rotation.
4. Use cached slot-placement metadata (`pivotToBox` + `boxSize`) captured once from the model’s neutral clone pose.
5. Place the model so the bottom of that stable bounding box rests on the slot surface.
6. Apply the final transform with `Model:PivotTo(...)`.

This keeps:

- one authoritative final movement method,
- centered X/Z placement on the intended slot reference,
- a slot-surface-based Y result,
- no cumulative reuse of a previously shifted live bounding box,
- deterministic repeated placement.

### Carry/grab cleanup added before final placement

Before final slot placement, the brainrot model’s internal assembly is treated as **untouchable**:

- no broad joint/attachment cleanup is allowed inside the NPC model,
- no welds, weld constraints, Motor6Ds, attachments, or other assembly objects are scanned and destroyed inside the brainrot model,
- temporary carry helpers are isolated outside the NPC model in `Workspace.NPCCarryHelpers`,
- cleanup removes only explicit carry-created helper instances referenced by the carry state,
- `Base`, `EPart`, and `XPart` are treated as protected permanent assembly parts,
- legitimate internal NPC assembly joints/welds/motors and billboard anchor parts are preserved as-is.

This distinction is critical:

- temporary carry helpers may be destroyed safely,
- real model assembly joints must remain intact so the whole brainrot moves as one assembled model,
- billboard anchor parts must stay attached to that intact assembly.

This is the safest approach because carry/place/redeem can still work while the NPC internals remain completely untouched. During carry, the complete brainrot model is kept anchored and moved as one unit at the front carry offset, while collision remains disabled through the carry collision group so it does not bug into the player.

### Temporary debug instrumentation

Placement tracing is now gated behind `OwnedNPCLevelConfig.DebugLogs`.
When enabled, the service logs:

- placement sequence number,
- placement reason/source,
- target slot and placement part,
- cached metadata source,
- carry/external movement artifacts found and cleaned,
- target pivot and resulting pivot,
- a delayed post-place drift check to catch any later re-move.

This was added specifically to confirm there is only one authoritative placement pass and to catch any later script or runtime state that tries to move the model again.

---

## Required brainrot model parts (Base / EPart / XPart)

All NPC/brainrot templates should include these named parts:

- `Base`: anchor for billboard GUIs
  - world/enemy display (`WorldNPCDisplay`)
  - owned/base display (`OwnedNPCDisplay`)
- `EPart`: anchor for grab prompt (`E`) when brainrot is owned in base
- `XPart`: anchor for delete prompt (`X`) when brainrot is owned in base

### Runtime binding behavior

- `NPCStateService` now prefers `Base` for world display anchoring.
- `BaseSlotService` now prefers `Base` for owned display anchoring.
- `BaseSlotService` now attaches:
  - grab prompt to `EPart`
  - delete prompt to `XPart`

If one of these parts is missing, service code warns and falls back to legacy anchor behavior so runtime does not hard-crash.

---

## Weapon Stock Shop System

A new modular server-authoritative weapon stock shop system was added.

### File/module structure

- `ReplicatedStorage/WeaponShop/Config/WeaponShopConfig.lua`
- `ReplicatedStorage/WeaponShop/Config/RarityConfig.lua`
- `ReplicatedStorage/WeaponShop/Config/WeaponShopRegistry.lua`
- `ReplicatedStorage/WeaponShop/Shared/WeaponShopFormatter.lua`
- `ServerScriptService/WeaponShop/Bootstrap.server.lua`
- `ServerScriptService/WeaponShop/Services/WeaponShopRemotes.lua`
- `ServerScriptService/WeaponShop/Services/GlobalStockRotationService.lua`
- `ServerScriptService/WeaponShop/Services/ServerStockStateService.lua`
- `ServerScriptService/WeaponShop/Services/WeaponOwnershipService.lua`
- `ServerScriptService/WeaponShop/Services/WeaponEquipService.lua`
- `ServerScriptService/WeaponShop/Services/WeaponPurchaseService.lua`
- `StarterPlayer/StarterPlayerScripts/WeaponShopUIController.client.lua`
- `StarterPlayer/StarterPlayerScripts/ShopOpenPart.client.lua`

### Setup assumptions and required UI hierarchy

The client controller expects:

`Shop > ItemShop > Items > Other > 1`

Where `1` is the template frame and contains:

- `Item/Icon` (`ImageLabel`)
- `Buy` (`TextButton`)
- `Rarity` (`TextButton`)
- `RobuxBuy` (`TextButton`)
- `ItemName` (`TextLabel`)
- `Price` (`TextLabel`)
- `Stock` (`TextLabel`)

Button text mapping notes:

- Buy/Equip text is written to `Buy/TextLabel`.
- Rarity text is written to `Rarity/TextLabel`.
- The controller does not rewrite `RobuxBuy` button text.
- Rarity visual color is applied to `Rarity.BackgroundColor3` (and rarity nested label color if present).

Stock timer mapping:

- `Shop > ItemShop > Time > TimeLabel` is updated live from server `NextResetUnix` as:
  - `Next Stock in M:SS`

Template `1` is hidden and cloned once per configured weapon.

### Open/close trigger part (touch/inside behavior)

`ShopOpenPart.client.lua` listens for local player presence inside `Workspace.OpenShopPart`.

- When player enters/stands inside `OpenShopPart`, `Shop > ItemShop` opens.
- When player leaves the part, `Shop > ItemShop` closes.
- Open/close uses `TweenService` with 1-second slide tween (moves in/out to the side).

### Tools source

Shop weapon tools are cloned on server from `WeaponShopConfig.ToolsFolderPath`.
Default path:

- `ReplicatedStorage/WeaponShop/Tools`

Each weapon config entry maps via `ToolNameInReplicatedStorage`.

### Global reset timing (all servers aligned)

Global timing is deterministic by Unix time:

- `CycleId = floor((now - CycleEpochUnix) / CycleDurationSeconds)`
- cycle boundaries are identical in all servers
- newly started servers compute current cycle immediately from wall-clock time

No server-start alignment assumptions are used.

### Deterministic stock generation (same roll in all servers)

For each cycle and weapon, initial stock is rolled by deterministic seeded logic:

- seed uses `(CycleId + weaponId + StockRollSalt)` via stable hash/xorshift
- stock is clamped to weapon `StockMin..StockMax`
- all servers compute identical initial stock per weapon for that cycle

### Per-server depletion behavior

Remaining stock is local per server:

- at cycle change, server resets local `remainingStock = deterministicInitialStock`
- purchases decrement only local server remaining stock
- other servers are unaffected until they consume their own local stock

This satisfies:

- global reset time + global initial stock values
- per-server stock depletion

### Ownership save system

`WeaponOwnershipService` stores per-player data in a dedicated DataStore:

- `OwnedWeapons` (set/map)
- `EquippedWeaponId`
- `ProcessedPurchases` (receipt id guard)

Includes retry/backoff, debounced saves, save-on-leave, and shutdown flush.

### Primary loadout rule

`WeaponEquipService` enforces one primary shop weapon tool:

- all shop-managed tools are marked with attributes:
  - `ShopManagedWeapon = true`
  - `ShopWeaponId = <weaponId>`
- before equipping a new **primary** shop weapon, existing primary shop-managed tools are removed from Backpack and Character
- then the target primary tool is cloned from ReplicatedStorage and equipped
- duplicate active primary tools are prevented

### Special PvP weapon coexist exception

- Weapon loadout behavior is now driven by `LoadoutSlot`.
- `LoadoutSlot = "Primary"` uses the normal single-primary replacement rule.
- `LoadoutSlot = "Extra"` uses a separate coexist path and does **not** replace the current primary weapon.
- Only `SteelSword` uses the extra slot in the current config, so it can stay in the player's loadout while another normal weapon is equipped.
- `SteelSword` is also the special contest/PvP weapon and carries:
  - `CanDamagePlayers = true`
  - `ContestDisarmEnabled = true`
  - `AttackHitboxSize`, `AttackRange`, `Damage`
  - `KnockbackHorizontal`, `KnockbackVertical`
- Other weapons continue replacing each other through the primary slot as usual.

### Purchase flows

Soft-currency purchase (`PurchaseWeapon`):

1. validate weapon id / enabled
2. reject if already owned
3. validate local server stock > 0
4. validate and deduct money (`DataService.TrySpendMoney`)
5. consume local stock
6. grant permanent ownership

Robux purchase (`RequestRobuxPurchase` + receipt):

1. prompt product purchase for configured product id
2. `ProcessReceipt` grants permanent ownership on success
3. stock is ignored for Robux unlock
4. duplicate grants prevented via processed receipt keys
5. after ownership is granted, weapon enters the same owned flow as soft-currency purchases (Buy state becomes Equip)

### Configuration fields

Per weapon in `WeaponShopConfig.Weapons`:

- `Id`
- `DisplayName`
- `ToolNameInReplicatedStorage`
- `Price`
- `Icon`
- `RarityId`
- `LoadoutSlot` (`Primary` or `Extra`)
- `StockMin`
- `StockMax`
- `RobuxProductId`
- `Enabled`
- `Damage`
- `AttackRange`
- `AttackHitboxSize`
- `CanDamagePlayers`
- `ContestDisarmEnabled`
- `KnockbackHorizontal`
- `KnockbackVertical`

Global shop config also includes:

- `EnableDebugWarnings` (set `false` to silence non-fatal WeaponShop warnings, `true` for debugging)
  - when `true`, `WeaponShopUIController` and `ShopOpenPart` will log binding/waiting/open-close diagnostics to help trace missing GUI/part issues

Rarities in `RarityConfig`:

- `Id`
- `DisplayName`
- `Color`

### Operational notes

- Weapons always appear in UI.
- Stock label is exactly:
  - `Stock: X` when stock > 0
  - `OUT OF STOCK` when stock == 0
- Shop button state is resolved from server ownership/loadout state:
  - unowned weapon => `Buy`
  - owned but not currently in the player's loadout => `Equip`
  - owned and currently equipped/loadout-active => `Equipped`
- SteelSword keeps its extra-slot coexistence behavior and still reports as equipped without breaking normal primary-weapon button states.
- Owned weapons do not require stock for re-equip.
- Stock only gates non-owned soft-currency buy in current server.

## NPC definition name resolution

NPC definition lookup now resolves names safely across:

- definition key
- `Id`
- `TemplateName`
- `DisplayName`
- normalized forms with whitespace removed

This lets systems keep working even when a brainrot name contains spaces (including multiple spaces), without breaking existing non-spaced identifiers.

## Defeated Capturable Flow (Kill -> Temporary Capturable -> Redeem)

The post-kill flow now uses a temporary defeated-capturable lifecycle instead of immediate send-to-base confirmation.

### Flow
1. Brainrot is killed.
2. Original combat brainrot is removed immediately by NPC state death handling.
3. Server fires a **death VFX hook** event (`CapturableLifecycle`, payload type `DefeatedVFXHook`) at death position.
4. Server waits `CaptureFlow.DefeatedRespawnDelaySeconds` (default `2`).
5. Server spawns a temporary capturable brainrot at the exact death `CFrame`.
6. Server fires a **spawn SFX hook** event (`CapturableLifecycle`, payload type `DefeatedSpawnSFXHook`).
7. Temporary capturable lives for the per-brainrot lifetime configured directly in `ReplicatedStorage/NPCSystem/Config/NPCDefinitions.lua` (`CapturableLifetimeSeconds`).
8. If lifetime expires before redemption, it is removed and becomes invalid.

### Temporary capturable behavior
- It is a separate lifecycle from combat NPC state.
- It removes inherited old interaction UI (`ProximityPrompt`) and old billboards (`BillboardGui`) on spawn.
- It is redeemable exactly once (guarded against duplicate redemption/races).
- It is grabbable by one player at a time.
- Temporary capturable grab prompt uses a **2 second hold** (`CapturableFlowConfig.GrabHoldDurationSeconds`).
- It cannot be placed into base slots directly.
- It uses a dedicated billboard template called `DefeatGui` for defeated temporary capturables only.

### `DefeatGui` field binding

Expected hierarchy:

`DefeatGui`
- `MoneyPS`
- `Mutation`
- `Name`
- `Rarity`
- `Time`

Field behavior:

- `MoneyPS` shows the defeated brainrot's income-per-second value.
- `Mutation` shows the current mutation display name.
- `Name` shows the brainrot display name.
- `Rarity` shows the rarity display name and rarity color.
- `Time` shows remaining lifetime as `⏰  XX`.

The timer updates live while the defeated capturable exists and stops automatically when the capturable is redeemed or expires.

### Carry-lock behavior for temporary capturables
- While carrying a temporary capturable brainrot, the player is locked into finishing or losing that carry flow before interacting with unrelated brainrots.
- During that lock, other temporary `DefeatedCapturableGrab` prompts are hidden and cannot be used.
- During that lock, owned base `Grab` / `Delete` prompts are also hidden and server-rejected if activation is somehow attempted.
- Owner-only prompt rules still apply underneath this lock, so prompts restore cleanly when the temporary carry ends.

### Carry + drop behavior
- Carrying temporary capturables is separate from base slot carry/place/swap flow.
- While carrying, server fires `CapturableCarryState` to toggle a dedicated carry GUI.
- The client now binds to the existing project hierarchy in `PlayerGui` and does not synthesize a replacement GUI:
  - `BrainrotCarryGui` (`ScreenGui`)
    - `DropButton` (`TextButton`)
      - `UICorner`
      - `UIStroke`
- The drop button is hidden by default and becomes visible **only** while carrying a temporary capturable.
- Clicking drop fires `CapturableDropRequest`, and the capturable returns to its original temporary spawn point.
- Dropping does **not** reset remaining lifetime.
- PvP contest release uses the same safe return path, so the brainrot keeps its remaining despawn timer.

### Redeem part behavior
- Redeem part is configured by `CaptureFlow.RedeemPartName` (default `BrainrotRedeemPart`).
- Touching redeem part while carrying a temporary capturable opens the existing confirmation prompt.
- On **Yes**: server sends brainrot to base via existing placement pipeline.
- On **No**: carry remains active.
- Touch debounce is controlled by `CaptureFlow.RedeemTouchDebounceSeconds`.

### PvP contest + safe zone behavior
- `BaseSlotService.ReleaseDefeatedCapturableForContest(player, reason)` safely forces a carried temporary capturable to return to its temporary spawn/return point.
- This path is used by the special PvP weapon and guarded against duplicate release processing.
- Safe-zone checks are handled by `ServerScriptService/NPCSystem/Services/SafeZoneService.lua`.
- Safe zones are any invisible `BasePart` descendants placed under `Workspace.SafeZones`.
- Recommended Studio setup for each safe-zone part:
  - `Anchored = true`
  - `CanCollide = false`
  - `Transparency = 1`
  - resize rectangular parts freely to cover the protected area
- Adding another part under `Workspace.SafeZones` automatically creates another protected safe zone.
- While a protected player is inside the safe zone, the special PvP weapon does **not** affect that player at all (no damage, no knockback, no disarm).

### New hooks/remotes
- `Remotes.CapturableLifecycleEventName` (`CapturableLifecycle`) for VFX/SFX/timer UI hook payloads.
- `Remotes.CapturableCarryStateEventName` (`CapturableCarryState`) to show/hide drop button.
- `Remotes.CapturableDropRequestEventName` (`CapturableDropRequest`) for drop action request.

### Notes
- Missing redeem part or missing VFX/SFX client assets fail gracefully (no crash).

## Combat hitbox + attack validation rework

### Client attack input
- Tool attacks are sent by `StarterPlayer/StarterPlayerScripts/ToolCombatController.client.lua`.
- `StarterPack/BasicSword/NPCClickAttack.client.lua` only marks the starter sword as an NPC combat tool; the shared controller handles the actual request.
- The client still uses click-to-attack, but server validation now splits NPC logic from player-hit logic.

### NPC attack validation (`NPCDamageService`)
- NPC / brainrot attacks stay **click-based**.
- They do **not** require exact mouse targeting on the NPC model.
- On attack click, the server finds the closest alive brainrot inside the weapon's allowed range, then validates against both:
  - the tool's `AttackRange`
  - the brainrot's configured `AttackRadius`
- If a valid brainrot is inside range, it takes damage even without precise mouse aim on the model.

### Player hit validation (`NPCDamageService`)
- Player-vs-player hits use the configurable **imaginary front-box hitbox** from `ReplicatedStorage/NPCSystem/Shared/CombatHitboxUtils.lua`.
- This PvP hitbox is validated with `PlayerHitboxSize` from the equipped weapon when present, otherwise it falls back to `AttackHitboxSize` and then the shared default config.
- The PvP hitbox uses a flattened forward direction for melee consistency and accepts overlapped body-part hits instead of re-validating only against the victim root part.
- This is separate from NPC click-range validation.
- It is **not** `Handle.Touched` based.

### Player vs NPC weapon behavior
- NPC hits: damage only.
- Player hits (only for weapons with `CanDamagePlayers = true`): damage + optional knockback.
- Contest disarm only runs for weapons with `ContestDisarmEnabled = true`, only on player targets, and only if the victim is currently carrying a temporary capturable brainrot.
- Safe-zone protection blocks the special PvP weapon's player effects entirely, but does not change NPC damage behavior.

## Base ownership visuals

### Owner-only `PlotGUI`

- Each base can contain `PlotPart > PlotGUI`.
- `PlotGUI` is handled locally on each client.
- A player only enables the `PlotGUI` for the base whose `OwnerUserId` matches their own user id.
- Other players do not see that base marker.
- Owned-slot `Grab` / `Delete` prompts are also hidden locally for non-owners, while owners still see and use them normally.

### Public owner `PlayerImage`

Expected hierarchy:

`Base`
- `BaseOf`
  - `GUIPart`
    - `SurfaceGui`
      - `PlayerImage`

Behavior:

- When a base is assigned, server-side base ownership logic sets `PlayerImage.Image` to the assigned player's headshot thumbnail.
- The image is visible to everyone.
- When the base is unassigned, the image is cleared.
- Reassignment refreshes the image for the new owner, preventing stale avatars from remaining on old bases.

### Centralized gameplay SFX
- Gameplay SFX are now configured in `ReplicatedStorage/NPCSystem/Config/GameplaySFXConfig.lua`.
- The actual sound templates are expected to be placed manually inside the configured gameplay SFX folder path.
- Server gameplay systems fire one shared remote through `ServerScriptService/NPCSystem/Services/GameplaySFXService.lua`.
- Client playback is handled centrally in `StarterPlayer/StarterPlayerScripts/GameplaySFX.client.lua`.
- The currently supported gameplay SFX hooks are:
  - `EnemyHit`
  - `EnemyKill`
  - `BrainrotGrab`
  - `BrainrotDrop`
  - `BrainrotPlace`
- Template folder/path and hook-to-template names can be changed from that single shared config without hardcoding sound setup into each mechanic.

### Alive NPC lifetime + billboard behavior
- Alive world NPCs now have a separate alive-lifetime countdown before they naturally despawn even if never defeated.
- `AliveLifetimeSeconds` can be configured per brainrot in `ReplicatedStorage/NPCSystem/Config/NPCDefinitions.lua`.
- If a definition omits `AliveLifetimeSeconds`, the server falls back to `NPCSpawnConfig.Lifetime.DefaultAliveLifetimeSeconds`.
- The alive timer starts when the NPC is spawned, and if the NPC is defeated first, the alive timer is ended by the normal death transition instead of fighting the defeated-state timer.
- The world billboard `Timer` label now shows the alive lifetime countdown in tenths like `60.9s`.
- `BrainrotLife > Progress` is resized from the current health ratio so full health fills the bar and 0 health empties it.

### Defeated timer formatting
- Defeated capturable billboards now use the same tenths-based countdown style like `60.9s`.
- Countdown expiry is aligned to the shared timer step so the tenths remain readable without materially extending the configured lifetime.

### Live Roblox base assignment ordering
- Player base assignment now begins immediately when the player session starts instead of waiting for datastore load to finish first.
- Slot restore waits safely until both the player data is loaded and the base exists, so a short live-Roblox assignment delay does not leave the player permanently unassigned/broken.

### Bat PvP behavior
- Bat-style PvP utility weapons still damage NPCs normally through the standard NPC combat path.
- Against players, the bat does **not** deal direct damage; it only applies PvP utility effects.
- Supported player PvP utility effects are:
  - strong knockback
  - contest/disarm of a carried temporary brainrot
- PvP utility is fully blocked by safe zones, so if either side is protected the hit applies no player damage, no knockback, and no disarm.
- Knockback strength remains configurable per weapon through `KnockbackHorizontal` and `KnockbackVertical` combat attributes in `ReplicatedStorage/WeaponShop/Config/WeaponShopConfig.lua`.
- Player knockback is applied on each valid hit using the repeated-hit PvP path, so later valid bat hits continue to push the same target instead of only the first one appearing to work.

### Absolute NPC attack radius validation
- NPC attack validation now uses the brainrot's configured `AttackRadius` as the authoritative NPC-hit boundary in horizontal space, so stepping inside the visible radius should allow attacks immediately instead of requiring extra inward movement from vertical-distance shrinkage.
- Weapon NPC validation still respects weapon range caps, but once a weapon's own range is large enough (for example SteelSword), the effective NPC boundary should feel like the brainrot radius itself.
- Player-vs-player hitbox logic is unchanged; this adjustment only affects the NPC range validation path.

### Mutation color configuration
- Full model mutation recolors are centralized in `ReplicatedStorage/NPCSystem/Config/NPCVisualConfig.lua` under `MutationVisuals`.
- `ModelColor` can override the full brainrot model color for each mutation.
- If a mutation does not provide `ModelColor`, the system safely falls back to that mutation's definition color from `MutationDefinitions`.
- Mutation color overrides are applied when world NPCs spawn, when defeated capturables are created, and when owned/base brainrots are cloned into slots.
- The same resolved mutation `Color3` is also used for the managed `MutationHighlight`, so highlight tint and model recolor stay in sync.
- `ReplicatedStorage/NPCSystem/Shared/NPCVisualUtils.lua` now destroys any previous managed `MutationHighlight` before creating a replacement, applies `OutlineTransparency = 1`, and forces `DepthMode = Enum.HighlightDepthMode.Occluded` so the tint does not render through walls.
- Highlight creation is centralized in `NPCVisualUtils.ApplyMutationColorOverride(...)`; no separate client/UI refresh script recreates mutation highlights in this repo tree.

### Rarity odds interpretation
- Rarity `Weight` values are now interpreted as literal odds denominators for the spawn roll:
  - `Weight = 50` means roughly a 1-in-50 roll
  - `Weight = 500` means roughly a 1-in-500 roll
- The rarity picker checks rarities from hardest-to-hit toward easiest-to-hit, and falls back to the easiest configured tier if none of the literal-odds checks succeed.
- This makes rarity rolls meaningfully less generous while keeping rarity behavior readable from the config.

### Mutation odds interpretation
- Mutation `Weight` values now use the same literal odds-denominator meaning as rarity weights.
  - `Weight = 50` means roughly a 1-in-50 mutation roll
  - `Weight = 100` means roughly a 1-in-100 mutation roll
- Mutation odds are configured in `ReplicatedStorage/NPCSystem/Config/MutationDefinitions.lua`, while `ReplicatedStorage/NPCSystem/Config/MutationConfig.lua` still holds the explicit no-mutation denominator (`NoneWeight`).
- `ReplicatedStorage/NPCSystem/Config/MutationRegistry.lua` now checks mutation weights from hardest-to-hit toward easiest-to-hit using the same literal-denominator roll style as rarity selection, so mutation generosity matches the new rarity interpretation.

### Place prompt visibility rules
- Owned-slot `Place` prompts are owner-only prompts.
- A `Place` prompt should only appear when all of these are true at the same time:
  - the slot belongs to the local player
  - the local player is currently carrying an owned/base brainrot in the valid place flow
  - the server-side placement flow currently has place prompts enabled for that base
- If the local player is carrying nothing, carrying a temporary unowned brainrot, or looking at another player's base, the `Place` prompt stays hidden.
- Another player's carry state should never make fake `Place` prompts appear for the local player.

### Initial spawn fill behavior
- Initial world brainrot filling is now staggered instead of spawning all points instantly at server boot.
- `NPCSpawnConfig.InitialFill.Enabled` controls the rollout, and `InitialFill.TotalDurationSeconds` sets the total target fill window (now tuned faster at about 45 seconds by default).
- On startup, spawn points are collected, shuffled into a random order, and scheduled one by one across that total duration.
- This only changes the initial server-start fill behavior; normal respawn, alive lifetime, and defeated-capturable lifetime logic stay unchanged.

### Tool/inventory lock while carrying
- Carrying **any** brainrot now locks tool usage for that player.
- When a carry starts, currently equipped tools are unequipped immediately.
- While carry is active, the client should close Satchel if it is open and call Satchel's `SetBackpackEnabled(false)` flow so the custom backpack/hotbar stays disabled.
- The combat remote path also rejects tool use server-side while carry is active.
- When carry ends, Satchel is restored with `SetBackpackEnabled(true)` without deleting or permanently removing any tools.

### EasyVisuals configuration for rarities and mutations
- EasyVisuals presets are centralized in `ReplicatedStorage/NPCSystem/Config/NPCVisualConfig.lua`.
- `RarityVisuals` maps rarity IDs to optional EasyVisuals presets/settings.
- `MutationVisuals` maps mutation IDs to both optional `ModelColor` overrides and optional EasyVisuals presets/settings.
- `ReplicatedStorage/NPCSystem/Shared/EasyVisualsController.lua` is the shared lifecycle helper that resolves the EasyVisuals module, avoids duplicate stacked effects, and destroys/rebuilds effects safely when UI objects change or are destroyed.
- `StarterPlayer/StarterPlayerScripts/NPCVisualEffects.client.lua` applies those configured rarity/mutation effects to tracked UI labels/objects so mutation UI effects and mutation model recolors can coexist cleanly.

### Temporary capturable carry speed penalty
- Carrying a temporary/unowned capturable brainrot applies a movement penalty only to that temporary carry flow.
- The penalty uses `BaseConfig.CarryRestrictions.TemporaryCarryWalkSpeedMultiplier`, which defaults to `0.9` (a 10% reduction from the player's current walk speed when the carry begins).
- The penalty does not stack across repeated carry refreshes.
- When the temporary carry ends because of drop, redeem, contest-disarm, reset, death, or cleanup, the stored pre-carry speed is restored.


### Max-level feedback
- Attempting to upgrade a level-100 brainrot is a clean failure path.
- The server sends a dedicated max-level feedback event instead of upgrading or spending money.
- The client plays `UpgradeInsufficientSFX` for that rejection and shows the configured max-level warning `TextLabel`.
- The warning label path is configurable with `OwnedNPCLevelConfig.MaxLevelLabelPath`, and if that label is not present the client safely falls back to the insufficient-funds label path.

## Rebirth system

### Overview
- Rebirth is server-authoritative and managed by `ServerScriptService/NPCSystem/Services/RebirthService.lua`.
- A rebirth can only happen if the player has enough current money for their **next** configured rebirth tier.
- On successful rebirth:
  - player money is reset/replaced with that tier’s configured reward money
  - rebirth progression advances by one tier
  - rebirth multiplier is set to that tier’s configured multiplier
- Multiplier behavior is **replace/set**, never additive stacking.
  - Example: rebirth tier x1.5 then tier x2 results in current multiplier x2 (not x3.5).

### Rebirth config
- Config path: `ReplicatedStorage/NPCSystem/Config/RebirthConfig.lua`.
- Tier list is fully data-driven (`RebirthConfig.Tiers`), each tier has:
  - `RequiredMoney` (big-number digit string)
  - `Multiplier` (number, e.g. `1.5`, `2`, `3`)
  - `RewardMoney` (big-number digit string)
- Add/edit/remove tiers directly in this array to control rebirth progression count and values.

### Saved data
- Rebirth data is persisted in `DataService` alongside existing save state.
- Save fields:
  - `RebirthIndex` (completed rebirth count / current progression index)
  - `RebirthMultiplier` (current active multiplier)
- Existing fields (`Money`, `Slots`, `BaseUpgrades`) are preserved and not wiped by rebirth.
- Rebirth only resets money, then assigns tier reward money.

### Money multiplier application
- Rebirth multiplier is applied in `DataService.AddMoney(...)` when new money is granted.
- Base slot income loops also apply rebirth multiplier in `BaseIncomeService` when accruing slot pending money.
- Spending logic (`TrySpendMoney`) and direct sets (`SetMoney`) remain unchanged.
- Multiplier uses floor behavior on scaled integer math for big-number compatibility.

### Base multiplier billboard (`Base > Multiplier > BillboardGui > Textlabel`)
- Assigned bases show owner multiplier as:
  - `<multiplier>x Money multiplier`
  - examples: `1x Money multiplier`, `1.5x Money multiplier`, `2x Money multiplier`
- This label refreshes when:
  - a player is assigned/bound to a base
  - saved rebirth data finishes loading (`RebirthMultiplier` attribute update)
  - rebirth succeeds and multiplier changes
  - a base is released/unassigned (resets safely to default ownerless value)
- Each base shows only its current owner multiplier; old owner text is cleared on release.

### Owned brainrot generation billboard refresh behavior
- Owned NPC `Generation` label now includes both:
  - real effective `/s` generation after rebirth multiplier
  - visible multiplier suffix `(xN)`
- Refresh triggers:
  - capture/place/restore into slot
  - level upgrade changes base slot income
  - player `RebirthMultiplier` attribute changes (load/rebirth updates)

### Server remotes
- Rebirth remotes are created in `ReplicatedStorage/NPCSystem/Remotes`:
  - `GetRebirthState` (RemoteFunction): returns current rebirth UI/server state for caller
  - `RequestRebirth` (RemoteFunction): validates and executes rebirth server-side
  - `RebirthStateChanged` (RemoteEvent): server pushes updated state to client

### GUI hierarchy (required)
- `GUI` (ScreenGui)
  - `Rebirth` (Frame)
    - `Bar` (Frame)
      - `Progress` (Frame)
      - `Text` (TextLabel)
    - `Recive` (Frame)
      - `Coins` (Frame)
        - `Text` (TextLabel)
      - `Multiplier` (Frame)
        - `Text` (TextLabel)
    - `Close` (ImageButton)
    - `RebirthButton` (ImageButton)
  - `Bottons` (Frame)
    - `BottonREBIRTH` (Frame)
      - `abrir` (ImageButton)

### GUI behavior
- Client controller: `StarterPlayer/StarterPlayerScripts/RebirthUIController.client.lua`.
- `abrir` opens rebirth frame, `Close` closes it, `RebirthButton` requests server rebirth.
- Bar updates:
  - `Bar.Text` displays current money / required money (compact currency)
  - `Bar.Progress` fills proportionally and clamps to [0, 1]
- Reward display:
  - `Recive.Coins.Text` shows next tier reward money
  - `Recive.Multiplier.Text` shows resulting multiplier (`xN`)

### TweenService open/close
- Rebirth frame open/close uses TweenService + UIScale for smooth pop animation:
  - open: scale up into view with easing
  - close: scale down out of view with easing
- Repeated open/close is guarded to avoid tween overlap race conditions.

### Max rebirth handling
- If player is already past the last configured tier:
  - no server error
  - request safely returns `MaxReached`
  - client UI keeps rendering safe max state and disables rebirth button interaction.
