# Adventurer's Kit: UI design

Every window looks like the quest panel: a dark tooltip background, a gold border, a thin orange
strip on the left of small boxes, an orange header in capitals, flat gold-edged buttons, a thin gold
scrollbar. All values below come from the existing code (`UI\Panel.lua`, `UI\PingAsk.lua`,
`Planner\Popup.lua`, `Planner\City.lua`, `Planner\Dungeons.lua`, `Planner\Farm.lua`,
`AdventurersKit_Buffs\Buffs.lua`, `UI\Options.lua`).

**New UI uses `NS.Style` (`AdventurersKit\UI\Style.lua`).** It holds the palette and the helpers
below, and loads right after `Core\Locales.lua`, so every file (and the Bags / Buffs addons through
`_G.QuestFocusNS`) can use it. The older windows still have their own copies of these values. If you
change a value in Style.lua, change the matching window too, or move that window to the helper.

## Palette

| Use | Value | `NS.Style` |
|---|---|---|
| Large window background (panel, city list) | `0.04, 0.04, 0.06, 0.93` | `BG` |
| Small box / popup background | `0.04, 0.04, 0.06, 0.92` (dialogs 0.94) | `BOX_BG` |
| Gold border, dividers, scrollbar, button edges | `0.95, 0.78, 0.40` (border alpha 1 on windows, 0.9 on boxes) | `GOLD` |
| Accent strip on the left | `1, 0.55, 0.25, 1` (quest popup: yellow `1, 0.82, 0`) | `ACCENT` |
| Small-box header (`BUFF REMINDER`) | `1, 0.6, 0.3` | `HEADER` |
| Window title (quest name, city list title) | `1, 0.86, 0.5` | `TITLE` |
| Section header (`OBJECTIVES`, `ALSO NEARBY`, stat box labels) | `0.75, 0.65, 0.45` | `SECTION` |
| Option description | `0.62, 0.62, 0.62` | `DESC` |
| Flat button background / selected segment | `0.08, 0.06, 0.03, 0.9` / `0.30, 0.22, 0.05, 0.9` | `BTN_BG` / `BTN_SEL` |
| Flat button and menu row hover | `1, 0.82, 0, 0.15` | `BTN_HL` |
| Clickable row hover | `1, 1, 1, 0.08` (whole-popup hover 0.06) | `ROW_HL` |
| Dungeon variant (dungeon list) | border `0.95, 0.45, 0.30`, title `1, 0.6, 0.45` | `DUNGEON_BORDER` / `DUNGEON_TITLE` |
| Progress bar | `0.95, 0.75, 0.2` (done: `0.3, 0.85, 0.3`), bar bg `0.15, 0.15, 0.15, 0.9` | |

Text colour codes (`NS.Style.HEX`):

- good / done: `|cff33ff99`;
- warning: `|cffff9933`;
- bad: `|cffff4444`;
- distance (`120 yd`): `|cff99ccff`;
- name or command in chat: `|cffffff00`;
- secondary value: `|cff999999`;
- a `label:` in front of a value: `|cffaaaaaa`.

Normal text is the white of `GameFontHighlightSmall`. Dim text is `GameFontDisableSmall`.

## Frame skeleton

Two kinds of frame, both from `CreateFrame("Frame", name, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)`:

| | Large window (panel, city list, dungeon list, share / copy windows) | Small box (buff reminder, quest popup, ping dialog, share dialog, toast, farm box) |
|---|---|---|
| bgFile | `Interface\\Tooltips\\UI-Tooltip-Background` | same |
| edgeFile | `Interface\\DialogFrame\\UI-DialogBox-Border` | `Interface\\Tooltips\\UI-Tooltip-Border` |
| edgeSize / insets | 20 / 5 | 12 / 3 (farm box: 14 / 4) |
| tile | `tile = true, tileSize = 16` | same |
| Accent strip | none | 2px, `TOPLEFT 4,-4` to `BOTTOMLEFT 4,4` |
| Header | icon 20px at `TOPLEFT 12,-11`, title `GameFontNormal` in `TITLE` colour | `GameFontNormalSmall` at `TOPLEFT 12,-8` (12,-7 on one-line boxes), `HEADER` colour, text in capitals |
| Close X | `UIPanelCloseButton` 24×24 at `TOPRIGHT -4,-4` (panel: -3,-3) | 20×20 at `TOPRIGHT -2,-2` |
| Strata | `MEDIUM` (dungeon list `HIGH`) | `MEDIUM`; dialogs that ask something `DIALOG` |

```lua
local S = NS.Style
local f = S.Box("AdventurersKitMyBox", 250, 60, L["MY BOX"])     -- box backdrop + accent + header + X
-- or step by step:
S.Backdrop(f, "box")            -- "window" for a large window; 3rd arg: border colour (dungeon variant)
S.Accent(f)                     -- orange strip; S.Accent(f, { 1, 0.82, 0 }) for the yellow popup one
f.header = S.Header(f, L["MY BOX"])
f.close = S.CloseButton(f)      -- S.CloseButton(f, true) for a large window
```

The "capitals" in a header are plain upper-case text in the `L[...]` key (`L["QFOCUS PING"]`), not a
font effect.

**Moving.** Every window can be dragged with the left button and is `SetClampedToScreen(true)`. Save
the top-left corner yourself in `QuestFocusDB` (not WoW's layout cache), re-anchor
`TOPLEFT, UIParent, BOTTOMLEFT, l, t`, and call `SetUserPlaced(false)`. The panel (`panelPos`) and
the farm box (`farmPos`) work this way. The quest popup saves its top centre (`qpopPos`), and a
right click on it resets the place.

```lua
S.Draggable(f, "myBoxPos")      -- drag + clamp + save { l, t } in QuestFocusDB.myBoxPos
S.RestorePos(f, "myBoxPos")     -- after ADDON_LOADED (QuestFocusDB exists then)
```

Windows that should close with Esc are added to `UISpecialFrames` (dungeon list, share window,
directions menu).

## Typography

| Role | Font object |
|---|---|
| Panel title (follows the font size option) | `QuestFocusFontTitle` (GameFontNormal, size + 2) |
| Panel rows and footer (follows the font size option) | `QuestFocusFontSmall` (GameFontHighlightSmall) |
| Window title | `GameFontNormal` |
| Box header, section header, flat button text | `GameFontNormalSmall` |
| Body text, list rows | `GameFontHighlightSmall` |
| Dim text: sub line, hints, footers, right column | `GameFontDisableSmall` |
| Question / big value (ping question, stat value) | `GameFontHighlight` |
| Options page title / tab | `GameFontNormalLarge` / `GameFontNormal` |
| Item count on an icon | `NumberFontNormalSmall` |

Panel sizes come from `NS.FontSize()` (8-20, default 10), `NS.RowH()` (`max(16, font + 6)`) and
`NS.PW()` (width, 300 at font size 10).

## Controls

**Flat button.** It replaces the red `UIPanelButtonTemplate` in our windows. Dark background, 1px
gold edges at 0.35 alpha, hover `BTN_HL` inside the edges, centred `GameFontNormalSmall` text, 22px
high (18px in lists). `NS.FlatButton(parent, text, w, h)` (PingAsk) and `S.FlatButton` are the same
button. The city list's `FlatBtn` also sizes itself to its text and can show a 13px icon before it.

```lua
local b = S.FlatButton(f, L["Ping in this group"], 136, 24)
b.text:SetFontObject("GameFontNormal")      -- bigger text for a main action
```

**Segmented selector.** A row of flat buttons, one selected. The selected one has the `BTN_SEL`
background and `GameFontHighlightSmall` text; the rest have `BTN_BG` and `GameFontDisableSmall`.
Buttons are 90×18 with a 3px gap (ping dialog).

```lua
local seg = S.Segmented(f, { { "ask", L["Ask"] }, { "on", L["Always ping"] } }, 90, 18)
seg.first:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
seg.onSelect = function(v) QuestFocusDB.pingMode = v end
seg:Select(QuestFocusDB.pingMode)
```

**Red circle (clear / abort / "don't watch this").** `Interface\\Buttons\\UI-GroupLoot-Pass-Up`,
with `-Highlight` (ADD) and `-Down`. It is 16px (panel focus clear, dungeon prep abort), or 14px at the
end of a row (buff reminder). Use `S.ClearButton(parent, size)`.

**Icon buttons in the panel's top row.** 16px, icon cropped with `SetTexCoord(0.08, 0.92, 0.08, 0.92)`,
`ButtonHilight-Square` (ADD) hover, a tooltip with a white title and a grey (0.8) description ending
in "Same as /qf ...". From the right: X, then options 6px left of it, then dungeon and farm 7px apart:
`[farm] [dungeon] [options] [X]`. A new one goes on the left of farm. A button that is off is
desaturated (farm). Use `S.IconButton(parent, icon, title, desc, onClick)`.

**◀ ▶ arrows.** `Interface\\Buttons\\UI-SpellbookIcon-PrevPage` / `-NextPage` with `-Up`, `-Down`,
`-Disabled`, hover `UI-Common-MouseHilight` (ADD), 18px. Use `S.ArrowButton(parent, "prev" | "next")`.
The buff reminder's choose-another arrow is `ChatFrame\\ChatFrameExpandArrow`, 12×22.

**Thin gold scrollbar.** `NS.AttachScrollBar(scrollFrame, onScroll)` (`UI\Panel.lua`), or
`S.ScrollBar(...)`, which calls it.
- It is an 8px wide bar on the right edge of the ScrollFrame.
- Track: 2px, gold at 0.18. Thumb: 3px, gold at 0.75; hover `1, 0.86, 0.5, 1`.
- Its height follows the visible part (at least 10px). Drag it, or click the track to jump.
- It only shows when the content doesn't fit. Call `bar.Update()` after the content changes.
- The city list and dungeon list still use `UIPanelScrollFrameTemplate`. New lists use the thin bar.

**Resize grip.** `Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up / -Highlight / -Down`, 16px at
`BOTTOMRIGHT -4,4`, above the content's frame level. Tooltip: "Drag to resize" / "Right click: reset
size". Save the size in `QuestFocusDB` (`panelH`, `citySize`); a right click clears it.
`S.ResizeGrip(frame)` makes the button; the sizing logic is yours.

**Dividers.** 1px gold line, inset 12px from both sides. Use 0.25 alpha (`S.Divider(parent)`); the panel's line under the header is 0.35.
The Options section header is `GameFontNormal` followed by a 1px `1, 0.82, 0, 0.25` line (`flow:Header`).

**Clickable rows.**
- A `Button` with a `GameFontHighlightSmall` (panel: `QuestFocusFontSmall`) text, `SetWordWrap(false)`, left aligned.
- An optional right column in `GameFontDisableSmall` / `GameFontHighlightSmall`, right aligned.
- Hover is a HIGHLIGHT texture `1, 1, 1, 0.08` (`S.RowHighlight(row)`).
- A tinted row has a BACKGROUND texture: city to-do rows `1, 0.6, 0.2, 0.10`, dungeon header rows `0.75, 0.25, 0.1, 0.14-0.30`.
- Left click acts; right click is the secondary action. Tooltips list both.

**Marquee text** (the buff reminder's warning rows, `Buffs.lua`). A fixed label, then a clipped box
(`SetClipsChildren(true)`) whose text scrolls left when it doesn't fit. It moves 25 px/s, waits 1.5s
at each end, and jumps back to the start:

```lua
row:SetScript("OnUpdate", function(self, dt)
    local over = (self.text:GetStringWidth() or 0) - (self.box:GetWidth() or 0)
    if over <= 2 then if self.off ~= 0 then self.off = 0; self.text:SetPoint("LEFT", self.box, "LEFT", 0, 0) end return end
    if self.wait > 0 then self.wait = self.wait - dt return end
    if self.atEnd then self.atEnd, self.off, self.wait = nil, 0, 1.5
    else
        self.off = self.off + dt * 25
        if self.off >= over then self.off, self.atEnd, self.wait = over, true, 1.5 end
    end
    self.text:SetPoint("LEFT", self.box, "LEFT", -self.off, 0)
end)
```

**Tooltips.** Use `NS.TT` (`UI\Tooltip.lua`) so they all share one structure:

```lua
local tt = NS.TT.Begin(self, "ANCHOR_RIGHT", title, rightText)  -- white title, grey right side
NS.TT.Sub(tt, text)    -- gold subtitle
NS.TT.Info(tt, text)   -- indented blue-grey info line
NS.TT.Note(tt, text)   -- grey wrapped note
NS.TT.Finish(tt, L["Click: ..."], L["Right click: ..."])  -- blank line + dark grey hints, Show()
```

A simple button tooltip is `SetText(title, 1, 1, 1)` and `AddLine(desc, 0.8, 0.8, 0.8, true)`. Every
`OnEnter` has `OnLeave = GameTooltip:Hide()`.

**Drop-down menu** (city list directions): a box backdrop with bg `0.06, 0.05, 0.03, 0.96` and a gold
border at 1, `DIALOG` strata, 170px wide. Rows are 18px with a 14px icon, a left label and a right
distance, and `BTN_HL` hover. The menu is in `UISpecialFrames`.

## Layout rules

- **Padding:** content starts 12px in from the left and right edges (panel rows `TOPLEFT 12`, dividers 12 / -12). Text in a box starts at x 12 after the accent strip (farm box without a strip: 10). Leave 8-10px between blocks and 3-4px between a label and its sub line.
- **Row heights:**
  - panel: `NS.RowH()` + 1px gap;
  - city list: 19;
  - city to-do and menu rows: 18;
  - buff reminder: 26 (22px icon);
  - flat buttons: 22, or 18 in a list.
- **Fixed size, scroll instead of growing.** In quest mode the panel has a fixed height (`QuestH()`): objectives scroll inside, and "also nearby" shows 3 rows plus a "+N more" row. The footer is one line (`SetWordWrap(false)`), so the height never changes in combat. Lists (city, dungeons) have a fixed number of visible rows and scroll. Only small boxes fit their text, between a minimum and a maximum width (farm box: 190-360).
- **Section headers** like `OBJECTIVES` / `ALSO NEARBY (in the macro too)` / `PROGRESS`: `GameFontNormalSmall`, `SECTION` colour, capitals, at x 14, with 15px below them (`S.Section(parent, text)`).
- **Icons before labels:**
  - 16px (14px in menus, 13px on flat buttons), 6px before the text;
  - `Interface\\Icons\\...` icons get `SetTexCoord(0.08, 0.92, 0.08, 0.92)` to cut the border (`S.TEXCOORD`);
  - minimap tracking and gossip icons stay `0, 1, 0, 1`;
  - inline icons in text: `|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t `.
- **Texture paths use double backslashes** in Lua strings: `"Interface\\Icons\\INV_Misc_Map_01"`. The lint (`tests\lint.ps1`) fails on a single one.

## Behaviour conventions

- **Combat:** nothing secure-sensitive in combat (macro edits, secure buttons, showing / hiding / moving secure frames). Check `InCombatLockdown()`, store what is pending, and do it on `PLAYER_REGEN_ENABLED` (see `Core\Events.lua`: `state.pendingBody`). Non-secure frames may update in combat, but must not change size.
- **Saved data:** positions and sizes are saved in `QuestFocusDB` (`panelPos`, `panelH`, `farmPos`, `qpopPos`, `citySize`). Per-character settings go in `NS.CharDB()` (its key also in `NS.CHAR_KEYS` if it used to be account-wide).
- **Options toggle:** every new popup or box gets an on / off switch in Options (`NS.AddOptionsTab` + `NS.OptFlow(page):Check(label, desc, get, set)`), with a short grey description under it.
- **Strings:** every user-facing string goes through `L["..."]`, written in English (the key is the English text). Code comments may stay Hungarian without accents.
- **Help text:** give every clickable thing a tooltip, and mention the matching `/qf` command ("Same as /qf ...").
- **Feedback** from a button click goes through `NS.Loud(...)`, so it reaches chat even when chat output is off.

## Checklist: adding a new window

1. Read this file. Build the frame with `NS.Style`: `S.Box(...)` for a small box, or `S.Backdrop(f, "window")` + `S.Header` / title + `S.CloseButton(f, true)` for a large one.
2. Header text in capitals through `L[...]`; every other string also through `L[...]`, in English.
3. Make it draggable and clamped: `S.Draggable(f, "myPos")` + `S.RestorePos(f, "myPos")` on load; right click resets where it makes sense.
4. Fixed size; long content scrolls with `NS.AttachScrollBar`, and rows use `S.RowHighlight`.
5. Buttons: `S.FlatButton` / `S.Segmented` / `S.ClearButton` / `S.IconButton`, never the red `UIPanelButtonTemplate` inside our frames (the Blizzard Options page itself may use it).
6. Tooltips with `NS.TT` (or the simple white title + grey line), and an `OnLeave` that hides them.
7. Nothing secure in combat; defer to `PLAYER_REGEN_ENABLED`.
8. Add an Options switch for it. Save its position in `QuestFocusDB`, and per-character data in `NS.CharDB()`.
9. Add it to `UISpecialFrames` if Esc should close it.
10. If it opens from the panel, it gets an icon button left of farm in the top row.
11. Texture paths with `\\`. Add the file to the .toc, then run the lint and offline tests (`tests\run.ps1`).
