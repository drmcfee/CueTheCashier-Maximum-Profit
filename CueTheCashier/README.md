# CueTheCashier: Maximum Profit 0.44.0 (auction house scanner and craft profit)

The addon was called CraftMarket until 0.38.0. 0.40.0 renamed the folders and 0.41.0 everything inside
(saved variables `CueTheCashierDB` and friends, the `CueTheCashier` Lua table, frame names). Data saved
under the old names is moved over by itself; macros that `/click` our old button names are updated at
login. The command is `/cmp` (`/cm` still works).

Change notes for every version are in `CHANGELOG.md` at the top of the repository. This file is
the detailed reference for each feature; the repository `README.md` is the quick guide.

CueTheCashier is free software under the GNU General Public License, version 3 or (at your option)
any later version. See `LICENSE`. You may use, share and change it, and changed versions must stay
open under the same license.

Install: copy all six folders, `CueTheCashier`, `CueTheCashier_Auctioning`, `CueTheCashier_Accounting`,
`CueTheCashier_Crafting`, `CueTheCashier_Destroying` and `CueTheCashier_History`, to
`World of Warcraft\_forever_\Interface\AddOns\` and restart the game. Files left over from older
versions in the `CueTheCashier` folder do no harm (the game only loads what the .toc lists), but you
can delete the folder first to keep it tidy.

## The suite

CueTheCashier is split into a core and modules, so the game only loads what you use:

| Folder | What it does | When it loads |
|---|---|---|
| `CueTheCashier` (core) | Prices, price sources, saved data, tooltip lines, vendor and disenchant values, debug log, skins, minimap button, the main window, `/cmp`, the public API | At login |
| `CueTheCashier_Auctioning` | Full scan, the Craft Trade window (Buy, Sell, Auctions, Post, Vendor, Snipe, Disenchant, Shopping) and buying | When the auction house opens, or `/cmp fullscan`, `/cmp test`, `/cmp button` |
| `CueTheCashier_Accounting` | The ledger (bought, sold, profit): the Ledger tab and Overview boxes of the main window | At a mailbox, merchant or the auction house, when the main window opens, on minimap hover, or `/cmp ledger` |
| `CueTheCashier_Crafting` | Finds your professions, reads their recipes, shows craft cost and profit in Blizzard's profession window, `/cmp prof` | At login |
| `CueTheCashier_Destroying` | Records your disenchants for `/cmp dis` | At login |
| `CueTheCashier_History` | 30 days of daily prices (data only) | When a scan or a longer average needs it |

Turning a module off in the AddOns list removes just that feature. `/cmp status` lists the modules
and whether they are loaded.

Every module has a checklist to run in game in `TESTING.md` (next to this file).

Use: open the auction house, click **Craft Trade** next to the X, then **Full Scan** (bottom right). Blizzard allows one
full scan per 15 minutes. Prices show on item tooltips.

Commands: `/cmp` (the CueTheCashier window), `/cmp settings`, `/cmp status`, `/cmp price <item link or id>`, `/cmp vendor <item>` (vendor price sources), `/cmp sources [item]` (every price source, with the item's values), `/cmp ledger`, `/cmp minimap`, `/cmp blocked` (calls Blizzard blocked), `/cmp realm` (server info), `/cmp dis` (your disenchants vs the table), `/cmp destroy [list]` (Destroy list), `/cmp macro [wheel|next]` (one-key macro), `/cmp prof` (professions report), `/cmp prof top` (best crafts), `/cmp prof list` (crafting list), `/cmp prof shop [auto]` (shopping list), `/cmp prof restock` (restock rules), `/cmp prof max <percent>`, `/cmp prof buy`, `/cmp prof dock` (Crafting List back next to the profession window), `/cmp prof move x y`, `/cmp prof button x y`, `/cmp item <id>` (everything the game says about an item), `/cmp test [item]`, `/cmp debug`, `/cmp log`, `/cmp skin [name]`, `/cmp reset`. `/cmp help` lists them all.

Debug test scan: `/cmp test [item]` searches only Light Leather (or the item you give) with a
normal search, so there is no 15 minute cooldown. The price is saved like a full-scan price.
Turning debug mode on opens the **debug log** window (`/cmp log`), which records every auction
house event and raw API reply. Click Select All, then Ctrl+C to copy it.
`/cmp fullscan force` (debug mode only) skips the addon's own 15 minute timer. The
server still has its own limit, so a forced scan may get no answer.

Saved data is split in two files so the game doesn't load everything at login:
- `CueTheCashier.lua` (loaded at login): per item the latest scan (min buyout, market value, median,
  mean, max, quantity, auctions, sellers), the 7-day and 30-day averages, the all-time average of
  every scan, and a sale rate field (empty for now; it will be filled from outside data later).
- `CueTheCashier_History.lua` (the CueTheCashier_History addon, loaded only when you scan or ask for
  another span): one point per item per day for the last 30 days.
Data from older versions is moved over at the first login. Tooltips show the 7-day and 30-day
averages; `/cmp price <item>` also shows the all-time average. Modules and other addons read it
through the API (below).
The ledger is saved in `CueTheCashier_Accounting.lua` and disenchant records in
`CueTheCashier_Destroying.lua` (0.14.0 moves them out of the core file once).

Craft Trade: a **Craft Trade** button next to the AH close button switches to CueTheCashier's own
auction window with Buy, Sell, Auctions, Post, Vendor, Snipe, Disenchant and Shopping tabs. Its **Auction House** button switches back.
**Profiles** (Settings tab, top): groups, operations, custom prices and the non-general settings are saved in a profile; each character uses one (its server and faction's own unless you pick another, so characters on one server share it), with Copy from, Reset and Delete.
**Open Mail** (mailbox, Inbox tab): click takes expired, cancelled and bought auction items; right-click takes the money from sales.
**Send Mail** (mailbox, Send Mail tab): sends items whose Mailing operation names a character, keeping Keep in bags, at most Send at most; whole stacks, 12 per mail.
**Sell to Vendor** (merchant window): sells what you bought on the Vendor tab or with Vendor Snipe (only that many, never your own copies); Shift-click also sells items whose Vendoring operation says to; up to 12 stacks per click.
**0.37:** **Skins** are easy to make: a tiny addon with one `Skins:Register` call (see `SKINS.md`); pick one in Settings > General > Skin. A built-in **Dark** skin shows how. The **server type** now comes from the server's rules (Normal, PvP, Roleplay, Roleplay PvP, Hardcore), and the server's number is saved with it (`/cmp realm` lists them); data saved under an old "Preset N" name moves over by itself. **Sale rate** is worked out from your own auction mails: of your auctions that sold or expired, the share that sold (2 or more needed; cancelled ones don't count). It shows on the tooltip with how many auctions it is based on.
**Main window, 0.36:** a **Gold** tab (gold per day for all characters or one, 30 days / 90 days / a year, as bars; saved once a day per character) and an **Inventory** tab (bags, bank, mail and auctions of every character on this server, per item, with market value; pick one character or all, search, click a header to sort). The **Ledger** tab's Profit view shows average buy and sell price and resale profit per item, and a new **Other** view lists repairs, postage, the auction house cut, deposits lost on expired and cancelled auctions (estimated) and gold traded. The Overview shows **Craft cooldowns** for every character (seen when you open the profession), and a chat line at login lists the ready ones.
**One-key macro** (0.35): `/cmp macro` makes a character macro "CueTheCashier" (`/click CueTheCashierOneKeyButton`); bind it to a key. Each press does the next step: accepts an open CueTheCashier confirm box, posts or cancels the Post tab's next line, buys the selected item on a deal tab, or disenchants the Destroy list's top item. **Settings > Auction house > One-key scroll wheel** (Off, Ctrl, Alt, Shift): hold that key and scroll to press it, one step per scroll; `/cmp macro next` says what the next press does.
**Destroy list** (0.35, `/cmp destroy`): uncommon and rare gear in your bags you can disenchant, best first, with disenchant and market value. The button (or the one-key macro) disenchants the top item, one item per press. Right-click a row to ignore an item; Shift+right-click the Item header to list ignored items again.
**Bank Moves** (0.35, bank window): To Bank / To Bags for items with a **Warehousing** operation (Keep in bags, Take to bags), or a whole group either way.
**Tooltip** (0.35): what an item disenchants into, with each material's chance; the disenchant value only on items that bind when equipped, or on everything if you know Enchanting. Both lines can be turned off in Settings.
**Buy** tab (0.34): **Level** boxes (lowest and highest required level), Filter > **Max % of value** (hides results priced over that share of their market value) and a **Saved** menu: your last 10 searches, searches you saved with a name (text, category, levels and filters), Save this search, Delete.
**Shopping** tab, **Group Scan** (0.34): looks up every item in your groups that has a Shopping operation and lists only the ones on sale at or under the operation's highest price, up to its Buy up to amount (counting bags, bank and mail).
**Auction house fees** (0.34): the cut is 5% at a faction auction house and 15% (a guess) at a neutral one (Booty Bay, Gadgetzan, Everlook); the deposit is about 20% of the vendor sell price. CueTheCashier notices which kind you opened last and uses it for craft profit and the price sources `cut` / `deposit`.
**Post** tab: **Post Scan** lists every bag item whose group has a Posting operation with the price and amount the operation gives; **Cancel Scan** lists your auctions someone undercut. The button at the bottom right posts or cancels the top line, one click each (Blizzard may want a confirm box for each). The names live at
the top of `CueTheCashier_Auctioning\CraftTradeUI.lua`; search for `CRAFT TRADE BUTTON`.

Vendor tab: **Search** looks through every item on the auction house right now (a normal browse
search, no 15 minute cooldown, but the server paces it so it takes a little while; the button says
**Stop** meanwhile). Items whose lowest price is below the vendor price are listed. Click one to load
its listings (the tab also loads them one by one after a search, and drops deals that are already gone): Below Vendor and Total Profit fill in, and **Buy** buys them right there. For stackables the
**Quantity** box starts at what your gold pays for. A buy that would not make a profit is refused. Stackables are
bought in one go after the server gives the exact price; single items are bought one auction at a time,
cheapest first. Every purchase asks first.

Snipe tab: watches for new postings. It repeats the same all-items search and only reports items whose
lowest price dropped since the round before (someone just posted them cheaper). **Snipe** reports prices
under the "Max % of market" box (default 60%) of the item's market value from your scans, or below vendor
price. **Vendor Snipe** only reports below vendor price. The first round after starting learns the current
prices. Leaving the tab or closing the auction house stops it. Buying works like the Vendor tab. Profit is
green when a vendor pays it for sure, yellow when it is measured against market value.

Disenchant tab: a live search for gear selling below its disenchant value. The value comes from the
classic disenchant table (quality, item level, armor or weapon) with materials priced from your scans,
and is also shown on item tooltips. Forever may differ from the classic table: every disenchant you do
is recorded, and `/cmp dis` compares what you got with the table. Treat the values as estimates until
that has been tested.

Listing lookups (Vendor, Snipe, Disenchant) start with the most profitable items, show "loading"
while waiting and "no answer" if the server never replied (each item is tried twice).

Professions ("prof": crafting, gathering and secondary skills): CueTheCashier keeps Blizzard's
profession window and only adds to it. In the recipe list, each recipe it can price shows its profit
(green) or loss (red) for one craft. Under the reagents of the selected recipe are three lines:
**Craft cost**, **Sells for** (auction value after the 5% auction house cut) and **Profit**; hover them
for each reagent's price and where it comes from. Each reagent is priced at the cheapest of the
auction house (market value, else lowest buyout), a vendor (reagents vendors sell) or crafting it
yourself with a recipe one of your characters knows. Professions are found at login; each window's
recipes are read when you open it, so open every profession window once (on Forever, Skinning,
Herbalism, Mining and Fishing have recipe windows too: Tanning, Gardening, Smelting, Bait and Tackle).
The profit number is green for a profit, red for a loss and white for none.

Crafting List: the **Craft List** button (left of Create All) offers **All profitable recipes** (every
profession of this character) or **Only <the open profession>**. The Crafting List window sits next to
the profession window and opens and closes with it. It shows what to craft, grouped under profession titles
(one of each; left-click a row for one more, right-click for one less) and the total profit. The **Add to list** button under a recipe's craft cost adds any recipe you know by hand (Shift for 5,
right-click for less), profitable or not. Click a
profession title to open that profession; click it again (with its window open) to craft the first
recipe there you have reagents for. Reagents that are cheaper to craft
yourself are added as crafts "for reagents" and made first. **Craft** crafts the next recipe on the list
that the open window can make; finished crafts come off the list. `/cmp prof list` opens it,
`/cmp prof button x y` moves the button (`top` for the window's top right, `reset` for the default).

Shopping List: everything the crafts need that is not in your bags, in sections: **Auction House** and
**Vendor** (what to buy, cheapest place, cost), **Mailbox** and **Bank** (click to take it out while
that window is open) and **Alts** (who has it, from their last visit). It opens by itself at the auction
house, a merchant, the mailbox or the bank when it has something for that place and stays open until you close it (`/cmp prof shop auto`
turns that off). Vendors you visit are remembered (name, place, what they sell; `/cmp prof vendors`), and clicking
a Vendor row puts Blizzard's map pin on the nearest one that sells it. Open the list with a right-click on the minimap button, from the Craft List button's menu or
with `/cmp prof shop`. One press of Escape closes it together with Blizzard's windows (and Craft Trade with the auction house). What you buy through CueTheCashier at the auction house counts
as in the mailbox right away. Items you have on the auction house are not counted yet.

Restock: under a recipe's craft cost, **Keep in stock** and **Min profit** make a rule for its item.
Craft List > **Restock items** queues enough crafts to get back up to that number, counting all your
characters, but only when one item makes at least Min profit.

Shopping: what the craft list still needs to get goes on CueTheCashier's shopping list. At the auction
house, the Craft Trade window's **Shopping** tab searches only the reagents that are cheapest on the
auction house, for the missing amount, up to a max price per item (120% of the price the craft list
used; `/cmp prof max <percent>` changes it). Click an item and Buy; every buy asks first. At a merchant
that sells reagents the list needs, a **Buy Reagents** button buys exactly the missing amounts after
asking (`/cmp prof buy` does the same). Clicking an Auction House or Vendor row on the Shopping List buys just that one: at the
auction house it opens the Shopping tab and brings up the buy box, at a merchant it asks to buy it there. `/cmp prof restock` writes every rule and
what it would do to the log.
Item tooltips show **Craft cost** for items you can craft. `/cmp prof` writes what CueTheCashier knows
about your professions to the log (`/cmp log`, copyable), `/cmp prof top` your most profitable known
recipes, and `/cmp prof move x y` moves the three lines if they sit badly. Enchants make no item, so
they show a cost but no profit. Saved in `CueTheCashier_Crafting.lua` (recipes shared by your
characters).

Vendor buy prices (used for craft costs): the base price of every profession reagent comes
from the game's own data for build 1.60.1.71037 (`VendorPrices.lua`, made by
`tools/build_vendor_prices.py` from wago.tools). Only reagents vendors actually sell get a price:
a known list (threads, vials, dyes, flux, salt, spices...) plus anything you see at a merchant
(since 0.15.0 also reagents the table doesn't have, and the table includes the reagents of the
Forever-only recipes of Skinning, Herbalism and Fishing). At a
merchant, CueTheCashier undoes your reputation discount (Honored 10%, Revered 15%, Exalted 20%) and
compares with the table; a higher price replaces it, a lower one is only logged (an unknown discount).
`/cmp vendor <item>` shows the price.

Main window: click the question mark button on the minimap, or type `/cmp`. Tabs along the bottom:
**Overview** (gold on your characters, auction data, profit, recent sales, best items), **Ledger**,
**Groups** (your item groups, see below), **Operations** (rule sets for posting, shopping, crafting, mailing, vendoring), **Prices** (price formulas, custom prices and every price source) and **Settings** (every
setting of CueTheCashier and its modules, including which tooltip lines show). Modules add their own
tabs, Overview boxes and settings through the API (`API.RegisterMainTab`, `API.RegisterOverviewSection`,
`API.RegisterSettings`, see MainWindow.lua).

Groups: a tree of groups and sub-groups. Unlike TSM, one item can be in several groups. Each item ranks
its groups 1, 2, 3... (since 0.39.0) and rank 1 wins where groups disagree. No two groups share a rank: moving
a group to rank 2 pushes the old 2 to 3. A group that gets the item later starts last. Change ranks in the
Groups tab: pick items on the right, then the rank box, **Up**, **Down** or **Make 1st** (bottom left; hover
the box for the item's groups in order). Old 1-100 priorities were turned into ranks once, highest first.
The **Base Group** at the top holds every item in the game (always last, so any other group wins); its operations will be the defaults. In a profession window, **Make Group** builds a group for that profession with sub-groups Items and Materials from your known recipes (click again to add new ones). Tooltips show an item's groups, the winner first in green. Groups can be exported as text and imported
again. Other addons read them through the API (`API.GetItemGroups`, `API.GetWinningGroup`, ...).

Price formulas (Prices tab, operation price fields): price sources by key or short name (`market`,
`min`, `7d`, `30d`, `vendor`, `vendorbuy`, `de`, `crafting`, ...), money (`100g`, `5s`, `1g 50s`), percent
(`90%`), `+ - * / ( )`, and `min()`, `max()`, `avg()`, `first()` (the first known value). Example:
`max(min(market, 7d) * 90%, vendor * 2)`. Save a formula under a name as a custom price and use it by
that name. Operations are made on the Operations tab and picked per group in Groups > Operations;
an item uses the operation of its winning group that has one, else the Base Group's.

Ledger: the Ledger tab of the main window (or `/cmp ledger`). **Bought** and **Sold** list
auction house purchases and sales. Buys made in CueTheCashier are recorded the moment they complete; buys
made in Blizzard's window and your sales come from the "Auction won" / "Auction successful" mails when you
open your mailbox (exact amounts, after the cut; a mail for a buy already recorded isn't counted twice), plus what you sell to and buy from vendors (seen by comparing
bags and gold at the merchant). **Profit** shows per item what you spent, received and made for today,
7 days or all time. Right-click a Bought or Sold line to delete it. Profit uses the average price you paid; items never bought count as free. Shared by
your characters on the same realm and faction. The ledger never hooks Blizzard's functions. Drag the
minimap button to move it, `/cmp minimap` hides or shows it.

Buying: WoW Forever only lets addons buy from a confirm box, so every buy asks first. Single items:
Buy -> confirm box -> bought. Stacks: Buy -> one box with the price -> bought, as long as the server's exact
price isn't higher than the box said (if it is, or Blizzard insists, a second box shows the new price). Vendor/Snipe refuse anything that isn't a profit. If Blizzard still blocks a
buy, CueTheCashier switches to Blizzard's window with the item's name in its search box so you can
finish there.

Debug log: `/cmp debug` logs buying, posting and errors; `/cmp debug verbose` also logs every search
(long). The log window has Pause so it can be copied.

Skins: see `CueTheCashier\Skins.lua`. Register a table with your own templates, fonts and bar colours;
anything left out falls back to the Blizzard look.

## For addon makers: the API

`CueTheCashier.API` is the stable way in (`API.lua` documents every function and message). CueTheCashier's
own modules use it too. It keeps working the same while `API.VERSION` stays 1.

```lua
local API = CueTheCashier and CueTheCashier.API
if API and API.VERSION == 1 then
  local market = API.GetPrice(itemID, "auction.market")      -- copper per item, or nil
  local sources = API.GetPriceSources()                        -- { { key, label, description }, ... }
  API.RegisterCallback("MyAddon", "CM_PRICES_UPDATED", function(message, kind, count) end)
end
```

Price sources: `auction.min`, `auction.market`, `auction.median`, `auction.mean`, `auction.max`,
`auction.min.7d`, `auction.market.7d`, `auction.min.30d`, `auction.market.30d`, `auction.min.all`,
`auction.market.all`, `auction.cut`, `auction.deposit`, `vendor.sell`, `vendor.buy`, `disenchant`, and from CueTheCashier_Crafting
`craft.cost`, `craft.value`, `craft.profit` (items one of your characters can craft). Modules can add more with
`API.RegisterPriceSource`. Also: `GetItemSummary`, `GetAverage`, `GetAllTimeAverage`, `GetHistory`,
`Get/SetSaleRate`, `GetVendorSellPrice`, `GetVendorBuyPrice`, `GetDisenchantValue`,
`GetDisenchantInfo`, `GetDisenchantOutcomes`, `FindItemID`, `GetServerKey`, `GetLastScanTime`,
`GetFullScanCooldown`, `RecordScan`, `FormatMoney`, and since API minor 1 `SetShoppingList(owner, items)` /
`GetShoppingList([from])` (message `CM_SHOPPING_LIST_CHANGED`), and since minor 8 `GetAuctionCutRate`, `GetAuctionDepositRate`, `GetAuctionDeposit(itemID, [count])`, `IsNeutralAuctionHouse`, and since minor 10 `GetMailKind`, `GetServerInfo`, `GetGoldHistory(days, [character])`; since minor 9 `IsEnchanter`, `IsBindOnEquip`, `MoveToBank([groupID])`, `MoveToBags([groupID])`, `AddOneKeyStep(owner, fn)`, `GetOneKeyNext`.

Messages: `CM_PRICES_UPDATED`, `CM_BUYOUT_PLACED`, `CM_STACK_PURCHASE_CONFIRMING`,
`CM_DEBUG_MODE_CHANGED`, `CM_MINIMAP_TOOLTIP`, `CM_MODULE_ENABLED`, `CM_MODULE_DISABLED`.

Writing a module: make a folder `CueTheCashier_<Name>` with `## Dependencies: CueTheCashier`, then
`local Module = CueTheCashier:NewModule("<Name>", { addon = ADDON_NAME, api = 1 })` and give it
`OnInitialize` / `OnEnable` / `OnDisable`. A module registers events, messages and `/cmp` commands
through itself (`Module:RegisterEvent`, `RegisterMessage`, `SendMessage`, `RegisterCommand`) and never
calls another module. For load on demand add `## LoadOnDemand: 1`,
`## X-CueTheCashier-LoadOn: <events or CM_ messages>` and `## X-CueTheCashier-Commands: <commands>`;
the core loads the module when one of those happens, then hands it that same event. See
`CueTheCashier\Modules.lua`.

## Guesses to check in game

Marked GUESS in the code:
- TOC Interface 16001 and the `_forever_` folder.
- The server rule flags (`Enum.GameRule.HardcoreRuleset`, `RPRuleset`, `PvPRuleset`) exist on Forever (seen in TSM's code; untested here).
- 15 minute full-scan cooldown (no API reports it, so the addon keeps its own timer).
- Buyout in the scan list is for the whole stack.
- One auction house per realm and faction (prices are stored per realm + faction).
- Light Leather is a "commodity" on Forever like on retail (the test scan handles both kinds).
- Scan button position on the auction house window.
- Saved prices survive a full game restart (broken in the Forever beta).
- Forever uses the retail-style profession window (`ProfessionsFrame`).
- The neutral auction house cut (15%) and deposit (20%); the faction rates (5%, 20%) were seen by Kim.
