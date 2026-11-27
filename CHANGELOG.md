# Changelog

All notable changes to CueTheCashier: Maximum Profit. Newest first.
Versions below 1.0 are beta: saved data is kept between versions, but settings and commands can still change.

## 0.46.0

- **One list: the Crafting List window is gone.** Its crafts are the Task List's "Profession crafts", and the
  Task List got its **Queue...** (click: from groups; right-click: all profitable, only this profession,
  restock) and **Clear** buttons, plus a profit total. Shift-click a craft for one more, right-click for one
  less. Your queued crafts carry over. The Task List opens with a profession window when crafts are queued.
- **Crafting from the list takes two clicks** when the profession window is closed: the first opens it, the
  second crafts. The game only starts a craft from a click made while its window is open (seen in game).
  Chat and the row's tooltip say so.
- **Crafter per Crafting operation.** A new "Crafter" field names the character who crafts the items. Other
  characters show them under "Crafted by other characters" on the Task List instead of queuing them. If the
  crafter doesn't know the recipe, the next character who does crafts it and the row says why.
- **Who should learn a recipe.** Recipe items (Pattern:, Recipe:, Plans: ...) say on the tooltip which of
  your characters should learn it and who knows it already. Settings > Item tooltips can turn it off.
- **"Vendor item, AH cheaper"** on Task List auction rows when a vendor sells the reagent too but the auction
  house is at least 5% cheaper; the tooltip shows both prices.
- **Vendor flip.** At a merchant where you have a reputation discount (Honored or better), the Task List lists
  items you can buy there and post on the auction house for a small, honest profit after the cut and deposit,
  priced under the full vendor price and at or under the cheapest auction. Click buys one stack. Markup 8% by
  default (Settings > Crafting, 0 = off); items with your sale rate under 25% are skipped.
- **Vendor it after too many reposts.** When the deposits lost on expired auctions since your last sale reach
  what the auction house earns over a vendor, the Post scan skips the item with "Vendor it" and the Sell to
  Vendor button sells it (when its Vendoring operation has Sell to vendors on). Vendoring operations can set
  their own limit: failed posts, or deposits as a % of the vendor price.
- Saved data: nothing moves. The ledger's sale numbers gain two fields (deposits lost, expired since last
  sale), rebuilt the next time you open a mailbox. New operation fields have empty/0 defaults. API minor 14
  (`API.GetRepostAdvice`).

## 0.45.0

- **Shopping List is now the Task List.** It holds more than things to buy, so the window, menus, minimap
  tooltip and help all say Task List. `/cmp prof tasks` opens it (`/cmp prof shop` still works). It keeps
  its saved spot and the "open by itself" setting.
- **New: Profession crafts** at the top of the Task List: every craft on the Crafting List, in the list's
  own order. A row says **craft** (green) when every reagent is in your bags: click it and the right
  profession window opens and the craft starts (as many as your bags allow, up to the queued count). A
  **missing** row (red) opens nothing; its tooltip and a chat line say what is missing.
- **"(low data)" mark** on the tooltip's sale rate and sold per day lines (yours and the region's) when they
  rest on fewer than 10 sold + expired auctions, so a rate from 2 auctions isn't trusted like one from 200.
  Settings > Item tooltips: "Low data mark" turns it off, "Low data below" changes the number. The desktop
  app's data can say how many player reports it has (`reports`) and gets the same mark.
- Fix: accepting a party invite while Craft Trade was open brought Blizzard's auction house window back on
  top of ours, and it stayed after the party ended. It is now hidden again whenever it comes back.
- **Windows come to the front when you click them.** The main window, Crafting List, Task List, debug log
  and Destroy window now share the game's normal window layer, so the one you click is drawn on top of the
  others (ours and Blizzard's). Before, some always stayed behind. Yes/no and "how many" questions still
  stay on top.
- Fix: each sold auction is written to the debug log once, not 2 to 4 times per Auctions tab refresh.
- Saved data: nothing moves or is renamed. Two new optional settings (`lowDataAt`, tooltip "lowData").

## 0.44.0

- **Commodity prices are shared across server types.** Stackable items (leather, herbs, ore, cloth, potions
  ...) look like they share one auction house over Normal, PvP, Roleplay and the other server types of a
  region. A scan on any of your characters now counts for all of them: commodities are also saved under
  "EU Commodities (all server types)", and prices come from the newest scan on any server type. Gear and
  other single items stay per server type and faction.
- Safe to switch: every scan still saves the server's own copy too, nothing is moved or deleted. Settings >
  Auction house > "Share commodity prices across server types" off goes back to only this server's scans.
- `/cmp region <item>` now also shows the shared line.

## 0.43.0

- **Your own sale numbers, on every character and server.** From your auction mails (the ledger) the
  addon now works out, per item: your **sale rate** (share of your auctions that sold; cancelled ones
  don't count, 2 needed), how many you **sold per day** over the last 30 days, and your **average sale
  price** (what you got each, after the cut). Every character on the same server and faction adds to it.
- **Region numbers.** Forever's server types (Normal, PvP, Roleplay, ...) all live in one region (EU).
  Everything your characters scanned or sold on any of them is merged: **region market value** and
  **region lowest buyout** (each server's 30-day average, averaged; servers not scanned for 30 days are
  left out), plus region sale rate, sold per day and average sale price.
- **New price sources** for formulas and operations (Prices tab, `/cmp sources`): `salerate`,
  `soldperday`, `saleavg`, `regionmarket`, `regionmin`, `regionsalerate`, `regionsoldperday`,
  `regionsaleavg` (long names `sale.*` and `region.*`). Sale rates are 0 to 1, so
  `market * salerate` works. The Prices tab shows them as 60% or 1.5, not as money.
- **Tooltip:** "Sold per day" and, once a character on another server type saw the item, "Region market
  value", "Region sale rate" and "Region sold per day". Each can be turned off in Settings > Item tooltips.
- **`/cmp region <item>`** lists what every server type in your region saw (lowest, market, 30-day,
  how long ago). Scan the same commodity (e.g. Light Leather) on two server types within a few minutes:
  identical listings mean they share one commodity auction house.
- Saved data: nothing moves. Prices stay per server type and faction as before. Sale numbers are kept in a
  new small table (`CueTheCashierDB.sales`) that is rebuilt from the ledger every time the mailbox opens,
  so it can't lose anything. Region numbers are worked out when asked and not saved.
- Ready for the desktop app: if an addon file sets `CueTheCashierAppData` (format in Data.lua), its
  region numbers are used first and the tooltip says "(app)".
- API minor 13: `API.GetSaleStats`, `API.SetSaleStats`, `API.GetRegionStats`, `API.FormatSourceValue`;
  price sources can be `format = "percent"` or `"number"`.

## 0.42.5

- Fix: "DealPage.lua:173: attempt to call a nil value" when the auction house closed (0.42.4). The
  modules now cope when the core `CueTheCashier` folder is older than they are, and say so in red in chat.

## 0.42.4

- **No list jumps to the top when you click in it** any more: Operations, Prices, Ledger, Inventory,
  Groups and every auction house list keep their scroll spot when they redraw (one shared helper,
  `CM.SetRows`). Only picking another group in the Groups tab starts its item lists at the top.

## 0.42.3

- **Send Mail:** the big "Send Mail (n)" button is gone. A small down arrow right of the To: box opens a
  menu: "Send by Mailing operations (n)" (your group items, as the old button did; hover for what goes
  where), Alts, Recently mailed (the last 15), Friends and Guild (online first). Picking a name fills in
  To:. The Inbox tab keeps Open Mail.

## 0.42.2

- **Queue... button on the Crafting List** (where Shopping List was; right-click it for the Shopping
  List). It opens a small window with your groups and tick boxes. Queue fills the Crafting List with the
  profitable recipes (by each item's Crafting operation) that make an item in a ticked group or its
  sub-groups; "Everything" ignores groups. Your ticks are remembered. Handy when another addon hides the
  Craft List button in the profession window. Also in the Craft List button's menu ("From groups...")
  and `/cmp prof queue`.

## 0.42.1

- **Post Scan lists everything sellable in your bags again** (Earthroot, a skinning knife...). The Base
  Group's Posting operation covers every item; only a group set to "None, not even the Base Group's"
  keeps its items out. Shopping, Mailing, Vendoring and Warehousing Base operations still only cover
  items in your groups.
- **Crafting List remembers where you drag it.** 0.42.0 had a bug that saved nothing. It now also
  starts right of anything on the profession window's right edge (Forever's profession tab buttons),
  measured each time the window opens.
- **Groups:** an item that also sits in a sub-group is greyed with "in <sub-group>" in the list, so
  it doesn't look forgotten (in the parent's list, and in a sister group's left list).
- **One look everywhere:** the Crafting List, Shopping List, debug log, Destroy window and question
  box now use the same frame as the auction house and main window (no portrait), with their lists on
  a dark inset and the same row stripes and highlight. A skin changes them all at once.

## 0.42.0

- **Defaults for Forever.** Posting operations undercut by 0c (Forever sells same-price auctions newest
  first, so undercutting only costs you). Crafting operations want a lowest profit of `crafting * 30%`
  (30% over the craft cost). Operations you made keep any value you typed yourself; fields you left at
  the default take the new one.
- **Base operations.** Every operation kind now has one called "Base", set on the Base Group (made once
  per profile; your own operations and Base Group choices are never changed, and a Base you delete
  stays deleted). Base Vendoring starts with selling off, Base Crafting queues one at a time. The Base
  Group's Posting, Shopping, Mailing, Vendoring and Warehousing operations only cover items that are in
  one of your groups; items in no group are never posted, mailed, sold or moved. Its Crafting operation
  covers every recipe (0.42.1: Posting too). In a group's Operations view, "None, not even the Base Group's" keeps the Base
  operation off that group's items (e.g. your Materials group for posting).
- **Crafting List** rows keep their place: one more or one less no longer moves them around. It
  remembers where you drag it next to the profession window (`/cmp prof dock` puts it back), and when
  another addon has something right of the profession window (a bar of profession tabs) it moves
  further right. The Shopping List also opens where you left it.
- **Not enough on the auction house?** When a recipe goes on the Crafting List N times but the
  auction reagents aren't all for sale under your top price (list price x `/cmp prof max`, 120%), a
  small box asks: none, what's for sale, or all. Counts come from the last full scan (scans from
  0.42.0 on save how many are for sale per price step).
- **Craft timer.** Crafting several at once (our Craft button, Blizzard's Create or Create All) shows
  `01:00/02:00` (time so far / time for the whole batch) next to the cast bar.
- **Shopping List** shows item names instead of numbers (names come from the last scan, or the game is
  asked for them and the list redraws).
- **Groups tab** lists stay where you scrolled when you click an item.
- **Post Scan** waits for the game to load your bag items first, so the first scan of a session finds
  everything (0.41 found 4 items, the next scan 10).
- **Bank Moves** button moved to the bottom right of the bank window, off the search box.
- **Debug clean-up.** The Test Scan button is gone (`/cmp test` still works) and Full Scan no longer
  opens the debug log (`/cmp log` does).

**Upgrading from CraftMarket (0.39 or older)?** Do this once, with the game closed:
1. Delete the old `CraftMarket` and `CraftMarket_*` folders from `Interface\AddOns\` and copy in the new
   `CueTheCashier` folders.
2. In `World of Warcraft\_forever_\WTF\Account\<your account>\SavedVariables\` rename these files
   (skip any you don't have): `CraftMarket.lua` to `CueTheCashier.lua`, `CraftMarket_Accounting.lua` to
   `CueTheCashier_Accounting.lua`, `CraftMarket_Crafting.lua` to `CueTheCashier_Crafting.lua`,
   `CraftMarket_Destroying.lua` to `CueTheCashier_Destroying.lua`, `CraftMarket_History.lua` to
   `CueTheCashier_History.lua`. On Linux, `tools/rename-saved-data.sh` can do it for you.
3. Start the game. If you forgot step 2, log out, close the game, rename, and start again.

## 0.41.0

- Every name inside the addon renamed to CueTheCashier: saved variables (`CueTheCashierDB` and friends), the
  `CueTheCashier` Lua table, frame names. Data saved under the old names is taken over once; macros that
  `/click` the old button names are fixed at login.

## 0.40.0

- Folders renamed to `CueTheCashier` and `CueTheCashier_*`. The core warns in chat if old `CraftMarket` folders
  are still installed.
- Our buttons and the Crafting List move to the first free spot when another addon has something where they
  would go.

## 0.39.0

- Group ranks (1, 2, 3...) replace the old 1-100 priorities; rank 1 wins where groups disagree.
- The Crafting List skips items you already have.

## 0.38.0

- New name: **CueTheCashier: Maximum Profit** (was CraftMarket), with the cash register icon. New command `/cmp`
  (`/cm` still works).

## 0.10 to 0.37 (CraftMarket)

Short version of the early betas:

- 0.37: skins as tiny add-on addons (`SKINS.md`), server type from the server's rules, sale rate from your own mails.
- 0.36: Gold and Inventory tabs, ledger Profit and Other views, craft cooldowns on the Overview.
- 0.35: one-key macro, Destroy list, Bank Moves, disenchant materials on the tooltip.
- 0.34: auction house fees in craft profit, Group Scan, saved searches and Buy filters.
- 0.31 to 0.33: profiles (per server and faction), Open Mail and Send Mail buttons.
- 0.29 to 0.30: Post Scan and Cancel Scan, selling to vendors.
- 0.23 to 0.28: the main window, groups, price formulas and operations.
- 0.15 to 0.22: the Crafting module: profit in the profession window, Crafting List, Shopping List, restock
  rules, remembered vendors with map pins.
- 0.14: split into a core and load-on-demand modules, with a public API.
- 0.13: vendor buy prices for profession reagents from the game's data.
- 0.11 to 0.12: price history moved to its own file, disenchant values.
- 0.10: the ledger and the minimap button. Every purchase goes through a confirm box (WoW Forever blocks addon
  purchases made straight from a button).
