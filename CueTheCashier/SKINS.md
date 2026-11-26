# Making a CueTheCashier skin

A skin changes how CueTheCashier looks without changing what it does. A skin only lists what it
changes. Everything it leaves out stays like the game's own look (the "Blizzard" skin).

## The quickest way: a tiny addon

1. Make a folder next to CueTheCashier in `Interface\AddOns`, for example `CueTheCashier_MySkin`.
2. Put `CueTheCashier_MySkin.toc` in it:

   ```
   ## Interface: 16001
   ## Title: CueTheCashier My Skin
   ## Dependencies: CueTheCashier
   MySkin.lua
   ```

3. Put `MySkin.lua` next to it:

   ```lua
   CueTheCashier.Skins:Register("My Skin", {
     colors = {
       highlight = { 0.2, 1, 0.4, 0.15 },   -- row under the mouse: green
       selected  = { 0.2, 1, 0.4, 0.25 },   -- clicked row
     },
     window = { background = { 0, 0.05, 0, 0.9 } }, -- dark green window background
   })
   ```

4. In game: Settings > General > **Skin**, pick "My Skin", then type `/reload`.

`CueTheCashier\SkinDark.lua` is a complete example (the built-in "Dark" skin).

## Every field

Colours are `{ red, green, blue, alpha }` with numbers from 0 to 1.

| Field | What it changes | Blizzard skin |
|---|---|---|
| `colors.stripe` | Every second row in a list | white, alpha 0.03 |
| `colors.highlight` | The row under the mouse | white, alpha 0.06 |
| `colors.selected` | The row you clicked | gold, alpha 0.15 |
| `colors.chartBar` | Bars on the Gold tab | gold, alpha 0.8 |
| `window.background` | A colour laid over CueTheCashier's windows | none |
| `progressBar.color` / `.background` / `.texture` | Scan progress bar | green bar |
| `titleButton.tint` | Colour of the Craft Trade button's border | gold |
| `buttonTemplate`, `checkTemplate`, `inputTemplate`, `insetTemplate` | Blizzard templates used for buttons, check boxes, text boxes and list frames | the game's standard ones |
| `windowTemplate`, `mainWindowTemplate`, `craftTradeTemplate` | Templates for the windows. Since 0.42.1 all three are `PortraitFrameTemplate`, so every window looks like the auction house window; the small ones (lists, log, Destroy, questions) hide the portrait and put their list on an inset (`insetTemplate`) | the game's standard ones |
| `fontNormal`, `fontSmall`, `fontStatus`, `fontLog` | Fonts | the game's standard ones |
| `inputMargin` | Space inside text boxes | 2 |

Templates must be ones the game (or another addon you load) provides. A wrong name makes the window
fail to open, so change templates only if you know the name exists.

The skin is saved for your whole account. CueTheCashier is GPL-3: a skin you share should be too.
