# CueTheCashier in-game test lists

One list per module. Run a module's list when it is new or changed, tick each line, and send
anything odd together with the debug log: `/cmp debug` first, then `/cmp log`, Pause, Select All,
Ctrl+C. Chat can't be copied, the log can.

Before every list: install all six folders, log in, `/cmp status` shows version 0.46.0 and every
module, and there is no Lua error box.

## One Task List, crafters, recipes, flips (0.46.0)

One list
- [ ] Open a profession window with crafts queued: no Crafting List window; the Task List opens instead.
- [ ] Task List buttons: **Queue...** (click: groups window; right-click: All profitable, Only <profession>,
      Restock items, From groups) and **Clear** (empties Profession crafts). Profit total at the bottom.
- [ ] Shift-click a craft row: one more. Right-click: one less. The list doesn't jump.
- [ ] Profession closed, click a green **craft** row: the profession opens and chat says to click again. Click
      again: it crafts.
- [ ] "Add to Task List" under a recipe in the profession window still adds it.

Crafter per Crafting operation
- [ ] Operations tab > a Crafting operation: set **Crafter** to another character's first name. Queue on this
      character: those items are not queued; **Crafted by other characters** lists "Name: 3 x Item".
- [ ] Log in on that character, queue: they are queued there.
- [ ] Crafter set to someone who doesn't know the recipe: the next character who does is used (hover the row).

Who should learn a recipe (needs each character to have opened its profession windows once)
- [ ] Hover a recipe item (Pattern:/Recipe:/Plans:): "Learn on <name> (your main ...)" and "Known by ...".
- [ ] One the main already knows: names another character with that profession.
- [ ] A recipe for a profession nobody has: "None of your characters has this profession: sell it".
- [ ] A recipe never seen in a profession window: grey "open the profession window once".

AH cheaper and vendor flip
- [ ] A reagent a vendor sells but the AH has 5% or more cheaper: its Auction House row says "(vendor item, AH cheaper)".
- [ ] At a merchant where you are Honored or better: the Task List shows **Vendor flip (10% discount)** with
      items that pay after cut and deposit. Hover: you pay, post at, profit each and per stack. Click: buys one stack.
- [ ] Settings > Crafting > "Vendor flip: markup %" at 0: the section is gone.

Vendor it after too many reposts
- [ ] Post a cheap item a few times and let it expire, open the mailbox, then Post scan: "Vendor it: N failed posts ...".
- [ ] With Sell to vendors on in its Vendoring operation, the merchant's Sell to Vendor button sells it.
- [ ] Vendoring operation "Vendor after failed posts" = 2: says Vendor it after 2 expired auctions in a row.

## Task List and low data (0.45.0)

Task List (was Shopping List)
- [ ] Right-click the minimap button, the Craft List menu (**Task List**), right-click **Queue...** on the
      Crafting List, `/cmp prof tasks` and the old `/cmp prof shop` all open a window titled **Task List**.
- [ ] It opens where the Shopping List was last dragged to (same saved spot), and still pops up by itself at
      the auction house, mailbox, bank and merchants (Settings > Crafting > "Open the Task List by itself").
- [ ] Queue a few crafts. The first section is **Profession crafts**: one row per craft, "2 x Name (Profession)",
      in the same order as the Crafting List. Clicking rows doesn't move the list.
- [ ] A craft with every reagent in your bags says **craft** (green). Close the profession window, click the
      row: the right profession opens; click it again and it crafts (0.46.0: two clicks, the game's rule).
- [ ] Gathering profs too: queue a Tanning (Skinning) recipe, close everything, click its row.
- [ ] Bank a reagent: the row turns **missing** (red), its tooltip lists what is missing (have / need). Click it:
      nothing opens, chat says what is missing.
- [ ] Bags only cover 1 of 3 queued: the row says craft; clicking crafts 1 and chat says so.

Low data mark
- [ ] An item you sold only a few times (under 10 sold + expired): the tooltip says "Sale rate (2 of your 3
      auctions sold) (low data)" in orange, and "Sold per day ... (low data)".
- [ ] An item with 10 or more: no mark.
- [ ] Settings > Item tooltips: "Low data mark" off hides it; "Low data below" set to 3 moves the line.

Bug fixes
- [ ] Craft Trade open, accept a party invite: Blizzard's auction house window does NOT appear over ours. Leave
      the party: still not there. Craft Trade buttons can all be clicked (nothing invisible on top). With
      `/cmp debug` on, the log says "Blizzard AH window came back (...), hidden again." when it happened.
- [ ] Auctions tab with sold auctions, refresh a few times: each "Sold auction" line is in the log once.
- [ ] Open the main window, Task List, `/cmp log` and Craft Trade so they overlap. Click each: it comes to the
      front. Blizzard's bags or character window over ours: click ours, it comes to the front. Nothing gets stuck behind.

## Shared commodity prices (0.44.0)

- [ ] `/cmp status` shows 0.44.0. Full scan on Malaeiel.
- [ ] `/cmp region Light Leather` has a line "EU Commodities (all server types)" with today's price.
- [ ] Log in a character on another server type. Hover Light Leather before scanning there: it shows
      Malaeiel's price (not "(old)" from an older scan there). A sword or other gear shows nothing new.
- [ ] Settings > Auction house: untick "Share commodity prices across server types". Light Leather now
      shows that server's own price (or none). Tick it again: the shared price is back.
- [ ] Shared AH check still wanted: scan Light Leather on two server types a few minutes apart and send me
      both `/cmp region Light Leather` outputs. If prices differ, untick the setting and tell me.

## Sale rate and region (0.43.0)

- [ ] `/cmp status` shows 0.43.0. Open the mailbox once (this works the sale numbers out).
- [ ] Hover an item you sold or that expired at least twice: "Sale rate (x of your y auctions sold)".
      Items you sold in the last 30 days also show "Sold per day (you, 30 days)".
- [ ] `/cmp price <item>` adds "Your sales here: N sold, N expired, N per day, X each on average".
- [ ] Prices tab: type an item you sold in Item. `salerate` shows as a percent, `soldperday` as a
      number, `saleavg` as money. Try `market * salerate` in Try: a price, no error.
- [ ] Log in a character on another server type (PvP, Roleplay, ...), full scan there, open its mailbox.
      Back on Malaeiel: hovering an item both scanned shows "Region market value (2 servers)".
- [ ] `/cmp region Light Leather` lists both servers with lowest, market and how long ago.
- [ ] Shared AH check: scan Light Leather on two server types within a few minutes. Send me both
      `/cmp region Light Leather` lines: the same lowest/market on both = one shared commodity AH.
- [ ] Settings > Item tooltips: turning "Sold per day" and "Region" off hides those lines.

## Core (CueTheCashier)

- [ ] Login prints "N prices loaded for EU Normal - Alliance" (or "No saved prices yet").
- [ ] Log out fully, restart the game, log in: the same number of prices is still there.
- [ ] Hover an item you have scanned: min buyout, market value (and 7/30-day lines once there is data).
- [ ] `/cmp price <item>`, `/cmp sources <item>`, `/cmp vendor <item>` answer without errors.
- [ ] `/cmp sources` lists `craft.cost`, `craft.value` and `craft.profit` (Crafting installed).
- [ ] Open a merchant that sells thread or vials: with `/cmp debug` on, the log shows no error;
      `/cmp vendor Coarse Thread` gives a buy price.
- [ ] `/cmp debug` then `/cmp log`: the window opens, Pause, Select All, Ctrl+C copies.
- [ ] Minimap button: hover shows today's spent/received/profit, click opens the CueTheCashier window, drag moves it.

## Main window (new in 0.23.0)

- [ ] `/cmp` alone opens the CueTheCashier window; `/cmp help` still lists the commands.
- [ ] Tabs along the bottom: Overview, Ledger, Groups, Operations, Prices, Settings. No Lua error.
- [ ] The window looks like Blizzard's own (portrait, title "CueTheCashier", gold tabs) and can be dragged.
- [ ] Overview: Gold shows this character's gold. Log in on an alt and back: "All characters" adds them up.
- [ ] Overview: Auction data (server, prices saved, last scan, full scan ready), Profit (today / 7 days / all time),
      Recent sales and Best items. Hover an item line: item tooltip.
- [ ] Ledger tab: Bought / Sold / Profit buttons top left, Today / 7 Days / All Time top right, all switch.
      Right-click a Bought line still asks, then deletes it.
- [ ] `/cmp ledger` opens the window on the Ledger tab; typing it again closes it.
- [ ] Prices lists every price source (incl. `craft.*`).
- [ ] Settings: two columns (General, Item tooltips, Auction house, Crafting). Hover a setting: help text.
- [ ] Untick Minimap button: the button goes; tick it: it comes back.
- [ ] Untick Market value (and Craft cost): those tooltip lines go away at once; tick to get them back.
- [ ] Debug mode tick = same as `/cmp debug` (log window opens).
- [ ] Snipe %: type 50, Enter, open the Snipe tab at the AH: it shows 50. Type 500 in Shopping %: refused,
      600 goes back to the old number.
- [ ] Untick "Open Craft Trade at the auction house": Blizzard's AH window opens next visit.
- [ ] `/cmp settings` opens the Settings tab. Escape closes the window, and opens the game menu like before
      (no "action blocked" error).
- [ ] Close the window on a tab, click the minimap button: it opens on that same tab.

## Groups (new in 0.24.0, main window Groups tab)

- [ ] Groups tab: **Base Group** at the top (gold, count "all"); clicking it shows what it is. Sub-group,
      Delete, rename and the right-click menu do nothing for it; it never shows in item tooltips.
- [ ] Groups tab: "No groups of your own yet". **New Group** makes one and puts the cursor in Name: type "Leatherworking", Enter.
- [ ] Pick it, **Sub-group**: "New Group" appears under it, indented, with a -/+ to fold it. Rename it "Armor Kits".
- [ ] Under a group's name: **Items** and **Operations** tabs (Items open first), with a line under them. Operations lists Posting, Shopping,
      Crafting and restock, Mailing, Vendoring, all "none" for now. The Base Group has them too; its
      Items view shows what the Base Group is.
- [ ] Two lists: left "In your bags, not here" (for a top-level group) or "In <parent>, not here" (for a
      sub-group), right "In this group". Click picks (gold), click again unpicks, shift-click picks a range,
      Select All picks all (again: none). **Add N** / **Remove N** move the picked items. Double-click or
      right-click moves one at once.
- [ ] Add item box: type `2318` (Light Leather), Enter: it shows on the right with its icon; the tree shows the count.
- [ ] Type an item name you have seen (e.g. Light Leather) in Add item: works too.
- [ ] Shift-click an item in your bags while the tab is open: it is added. Drag an item onto the list: added.
- [ ] (0.39) Make a group "Mats" and add Light Leather to it too. Mats got it last, so in Mats it shows
      orange "2/2"; in Leatherworking green "1/2".
- [ ] Hover Light Leather anywhere: tooltip lines "Groups  1. Leatherworking" (green) and "2. Mats".
- [ ] Pick Light Leather on the right in Mats, click **Make 1st** (or **Up**, or type 1 in the box): now Mats
      is green 1/2 and Leatherworking orange 2/2; tooltip too. Hover the box: both groups in rank order.
- [ ] A third group with Light Leather starts at 3/3. Type 1 in its box: it becomes 1, the old 1 and 2 move to 2 and 3.
- [ ] Your groups from 0.38 kept their order: the group with the higher old priority is now rank 1.
- [ ] Right-click a group: menu with New sub-group, Move into (pick another group / Top level), Export, Delete.
      Moving a group into its own sub-group isn't offered.
- [ ] **Export**: text box with the group text, already selected; Ctrl+C. **Import**: paste it back: nothing is
      doubled ("0 new groups"). Delete a group, import again: it comes back with its items and ranks.
- [ ] Delete asks first and says how many sub-groups go with it.
- [ ] Settings > Item tooltips > Groups unticked: the group lines leave the tooltip.
- [ ] /reload: groups, priorities and folded groups are still there.
- [ ] Open Leatherworking (or any profession): a **Make Group** button sits left of Craft List. Click it:
      chat says how many items and materials; the Groups tab shows Leatherworking > Items and > Materials.
- [ ] Click Make Group again: "0 new". Learn a recipe, click again: only the new ones are added.
- [ ] `/cmp prof group` does the same with a profession window open.

## Price formulas and operations (new in 0.28.0)

- [ ] Prices tab: type `min(market, 7d) * 90%` in Try, an item you scanned in Item (or shift-click one):
      "= <money>". Try `market *`: a red error. Try `max(1g 50s, market)`: works (1g 50s is one amount).
- [ ] Price sources list shows the short names in gold (market, 7d, vendor, crafting ...) and the item's values.
- [ ] Custom price: Name `mybase`, Formula `max(market, vendor * 2)`, Save: it is listed with its value.
      Then `mybase * 90%` works in Try. Click it, change the name, Save: renamed. Delete asks first.
- [ ] Naming a custom price `market` is refused.
- [ ] Operations tab: Posting, Shopping, Crafting, Mailing, Vendoring in gold on the left.
      Click a kind, **New Posting**: "Posting" appears and is opened; rename it.
- [ ] Posting fields: Lowest / Normal / Highest price, Undercut by, the two choice buttons (menu with options),
      Most to have posted, Keep in bags, Duration, Cancel when undercut. Hover a label: help text.
- [ ] Type `market *` in a price field, Enter: red error at the bottom, the old value comes back.
- [ ] Test item (or shift-click an item): each price field shows its value for that item.
- [ ] **Copy** makes "Posting 2"; **Delete** asks and says how many groups use it.
- [ ] Groups > a group > Operations: **Choose** next to Posting: menu with None, your operations, New, Edit.
      Pick one: the line shows it; a sub-group shows it in grey "(from <parent>)".
- [ ] Give the Base Group a Shopping operation: a group without one shows "Base Group default: <name>".
- [ ] Rename the operation on the Operations tab: the group view shows the new name. Delete it: "none".
- [ ] /reload: custom prices, operations and group choices are still there.

## Post and Cancel scan (new in 0.29.0, Craft Trade > Post tab)

Set up first: an operation under Posting (Operations tab), put it on a group (or the Base Group) holding
a few items you have in your bags. Leave Cancel when undercut on.
- [ ] Formulas: `crafting` works in Try (craft cost); an old formula using `cost` still works but `cost` is
      not listed. The New button on the Operations tab fits "New Crafting".
- [ ] Craft Trade has a **Post** tab after Auctions. **Post Scan**: each bag item with a Posting operation
      gets a line; "looking up" turns into Post (green) or Skip (grey) with the reason in What.
- [ ] Check a Post line: price = cheapest other auction minus Undercut by, never under Lowest or over
      Highest; Qty = Most to have posted minus what you already have up, minus Keep in bags.
- [ ] An item nobody else sells posts at Normal price (or Highest if you chose that).
- [ ] Click **Post** (bottom right): it posts the top line and goes on to the next. Say if Blizzard blocks it
      (then a confirm box comes up for each one: tell me how that feels). Check the auctions in Blizzard's tab:
      right duration, price, stack/qty.
- [ ] **Skip** jumps over a line. **Stop** during a scan stops it.
- [ ] Get undercut on something (or post one high), then **Cancel Scan**: it is listed as Cancel. Click Cancel:
      it is taken back (and Blizzard's cancel fee, if any).
- [ ] Send me the /cmp debug log if a line says "no answer from the auction house".
- [ ] Auctions tab: a sold auction reads "Sold: <item>" with Sold: in green, the money in the buyout
      column, and the time until the mail comes (like "20m") on the right, as in Blizzard's window.

## Skins, server rules, sale rate (0.37.0)
- [ ] Login: still "prices loaded for EU Normal - Alliance" (nothing moved on a Normal server).
- [ ] `/cmp realm`: "Server number 1, type from rules: Normal" and "Known server EU-1 = Normal".
      On another server type later: it should name it (PvP, Roleplay, ...), and tell me its number.
- [ ] Settings > General > **Skin**: pick Dark, /reload. Lists get blue highlights and windows a darker
      background. Pick Blizzard and /reload to go back.
- [ ] Sale rate: after 2+ of your auctions of one item have sold or expired (and you opened the mail),
      its tooltip says "Sale rate (3 of your 4 auctions sold) 75%".

## Accounting extras (0.36.0)
- [ ] `/cmp` > **Inventory** tab: your items in bags, bank, mail and auctions with value. Open the bank and
      mailbox once first. The character button switches between all characters and one; the search box filters.
- [ ] **Gold** tab: one bar per day (only today until more days pass). Hover a bar for the date and gold.
- [ ] Ledger > **Other**: repair at a vendor (a "Repairs" line), send a mail ("Postage"), sell on the AH
      ("AH cut" from the sale mail), let an auction expire ("Expired", deposit estimate), trade gold ("Trade").
- [ ] Ledger > **Profit**: Avg Buy, Avg Sell and Resale per item.
- [ ] Craft cooldowns (when you have one, e.g. a transmute): open the profession, then the Overview lists it
      with the time left; at login a chat line says which are ready.

## Destroy list, bank moves, one-key macro, tooltip (0.35.0)
- [ ] Tooltip on green/blue gear: "Disenchants into:" with each material, amount and chance. The
      Disenchant value line shows on items that bind when equipped, and on everything for an enchanter.
- [ ] `/cmp destroy`: lists your uncommon and rare gear, best value first. Disenchant (n) disenchants the
      top item, one per click; the list updates after each. Right-click a row to ignore an item.
      It closes when combat starts. Send me the log if a click does nothing.
- [ ] Bank: a **Bank Moves** button on the bank window (tell me if it sits in a bad spot). Give a group a
      Warehousing operation (Keep in bags 5): To Bank leaves 5 in your bags. Take to bags 12: To Bags
      brings it back up to 12. "A whole group" moves everything in that group.
- [ ] `/cmp macro` makes the "CueTheCashier" macro; bind it to a key. With the Post tab after a Post Scan,
      each press posts the next line (a second press accepts the confirm box if Blizzard asks).
      On Vendor/Snipe/Shopping: select an item, press = Buy, press again = Accept. With /cmp destroy open:
      press = disenchant the top item.
- [ ] 0.35.1: Settings > Auction house > **One-key scroll wheel**: pick Ctrl (or Alt/Shift). Hold it and scroll:
      each scroll does the next step, like the macro. Off gives the wheel back. Survives /reload.
- [ ] Operations > Posting > Duration offers 2 / 8 / 24 hours. An operation saved with the old 12/24/48
      shows 2/8/24 (same game choice as before). Tell me which duration the 20% deposit was for.

## Fees, Group Scan, saved searches, filters (0.34.0)
- [ ] Open a faction auction house with `/cmp debug` on: the log says "Auction house: faction (cut 5%)".
      At Booty Bay, Gadgetzan or Everlook it should say "neutral (cut 15%)". Tell me what the real neutral
      cut and deposit are if you post there.
- [ ] `/cmp sources <item>`: Auction house cut = 5% of market value, Auction deposit = 20% of vendor sell price.
      A custom price like `cut + deposit` works too.
- [ ] Profession window tooltip says "After the 5% auction cut" (15% after you used a neutral one).
- [ ] Shopping tab > **Group Scan**: give a group a Shopping operation (max price, Buy up to). Only items
      on sale at or under the max price stay in the list; Need = Buy up to minus what you have (empty = no limit).
      Buying works like Search.
- [ ] Buy tab: type 10 and 20 in the **Level** boxes and search: only items for levels 10-20.
- [ ] Buy tab: Filter > Max % of value > 80%: only results at or under 80% of their market value
      (items you never scanned are hidden too). "No results found. N were over 80%..." when all are hidden.
- [ ] Buy tab: **Saved** > Recent lists your searches; click one to run it again with its filters.
      **Save this search...** asks for a name; the saved one comes back after /reload. Delete removes it.

## Per-server profiles (0.33.0)
- [ ] Settings > Profile now shows your server's name ("EU Normal - Alliance"), with everything you had.
      Every character on that server shares it unless it picks another. A character on another server
      (or the other faction) starts with an empty profile of its own; Copy from brings yours over.
- [ ] Operations > Mailing: **This character** next to Send to character fills in the name of the
      character you are on.

## Mailbox buttons (0.32.0, changed in 0.32.1)
- [ ] 0.32.2: ONE button, top right (0.32.1 drew two on top of each other). Inbox tab: **Open Mail (n)**. Send Mail tab: **Send Mail (n)**. Switching
      tabs swaps them. Left-click Open Mail: expired, cancelled and bought auction items. Right-click: money
      from sales only. The number goes down as mails are opened (and is right a second after it finishes).
- [ ] At any mailbox two buttons at the top right: **Open All (n)** and **Send Mail (n)**. Send Mail is greyed
      out when nothing goes; hover says why. Tell me if they cover something.
- [ ] Open All: click takes money and items from every mail (not cash on delivery, not Blizzard mail).
      Right-click (or Shift-click): menu All / Sales / Auction buys / Expired / Cancelled with counts.
      Stops when bags are full. The ledger still records sales and buys (check the Ledger tab).
- [ ] `/cmp mail` writes your Mailing operations, their groups and what would be sent to the log.

## Profiles and Mailing (new in 0.31.0)
- [ ] After updating, everything you had (groups, operations, custom prices, tooltip lines, Snipe %) is still
      there: it moved into the profile "Default".
- [ ] Settings tab, top: Profile [Default (change)]. Type a name, **New Profile**: this character now uses an
      empty profile (no groups or operations). The profile button menu: Use profile, Copy from, Reset, Delete.
- [ ] Log in on another character: it still uses Default. Pick the new profile there too: both share it.
- [ ] Copy from Default into the new profile: the groups and operations come back. Delete it: back to Default.
- [ ] Mailing: make a Mailing operation (Send to character = your alt's first name), put it on a group with
      items in your bags. At a mailbox a **Send Mail (n)** button shows (top right of the mail window; tell
      me if it covers something). Hover: what goes to whom. Click: one mail per 12 stacks, sent one after
      the other. Keep in bags and Send at most are respected (whole stacks only).
- [ ] A wrong name: "A mail could not be sent" and it stops.

## Sold sum and selling to vendors (new in 0.30.0, button fixed in 0.30.1)
- [ ] 0.30.2: a plain click sells only what you bought to vendor; Shift-click also sells the Vendoring
      operation items. The hover lists the two parts separately.
- [ ] 0.30.1: at a vendor the button now shows whenever the to-vendor list has something (greyed out when
      none of it is in your bags). `/cmp tovendor` writes the list and what it would sell to the log;
      `/cmp tovendor add <shift-click item> 5` adds 5 by hand; `/cmp tovendor clear` empties it.
- [ ] Auctions tab: left of Cancel Auction, "Sold: <money>" = the sum of the green Sold rows. Compare with
      what arrives in the mail (is the 5% cut already taken off?).
- [ ] Buy something on the Vendor tab (or Vendor Snipe). /reload is fine. Go to any vendor: a
      **Sell to Vendor (n)** button at the top of the merchant window (tell me if it covers something).
      Hover: what it will sell and why, the total, and how many are still in the mail or bank.
- [ ] Have some of the same item of your own in your bags: the button sells only the bought ones. Whole
      stacks only; if only part of a stack should go, it says to split it by hand.
- [ ] Click: sells up to 12 stacks, then prints what it got. The vendor's Buyback tab can undo it.
- [ ] Selling them by hand at a vendor counts the list down too. Posting them on the AH instead shrinks it.
- [ ] Vendoring operation: give a group a Vendoring operation (Sell to vendors on). Items of that group in
      your bags worth less on the AH than "When auction value is under" are listed too, keeping "Keep in
      bags". Items never seen on the AH are never sold this way.

## Fixes in 0.29.1
- [ ] Give a group (or the Base Group) a Crafting operation with Most to craft at once 5 (or 20). Craft List >
      All profitable: each item in that group is queued 5 (20) times, not once. Only items earning at least
      Lowest profit each are listed.
- [ ] Set Keep in stock 3 in that operation: the list queues only what is missing (bags, bank, mail, alts and
      your auctions), at most Most to craft at once. Craft List > Restock items does the same.
- [ ] Items without a Crafting operation still work as before (profitable ones, once each).
- [ ] Auctions tab: sold auctions show the money again (with Sold: and the time). With /cmp debug on, the log
      has a "Sold auction ..." line per sold auction: send me one so I can check the numbers.
- [ ] /cmp debug during a full scan no longer floods the log with REPLICATE_ITEM_LIST_UPDATE.

## Auctioning (CueTheCashier_Auctioning)

- [ ] Open the auction house: the **Craft Trade** button sits next to the X; `/cmp status` shows the module loaded.
- [ ] Craft Trade: every tab (Buy, Sell, Auctions, Vendor, Snipe, Disenchant, Shopping) opens without errors.
- [ ] **Full Scan** finishes and prints how many items were saved; tooltips update.
- [ ] Buy tab: search an item, open it, buy one cheap single item (confirm box, then bought).
- [ ] Buy a small stack (one confirm box, bought; or a second box if the price moved).
- [ ] Sell tab: post one item; it shows on the Auctions tab; cancel it.
- [ ] Vendor and Snipe tabs: Search/Snipe run and can be stopped.
- [ ] **Auction House** button switches back to Blizzard's window; closing the AH stops any search.

## Accounting (CueTheCashier_Accounting)

- [ ] A buy made in Craft Trade shows on the Ledger tab's Bought view at once.
- [ ] A buy made in Blizzard's window shows after you open the mailbox (once, not twice).
- [ ] A sale shows on Sold after the "Auction successful" mail is opened.
- [ ] Sell something to a vendor and buy something from one: both show.
- [ ] Profit view: today / 7 days / all time switch. Right-click a Bought line asks, then deletes it.

## Destroying (CueTheCashier_Destroying)

- [ ] Disenchant a green item: with `/cmp debug` on, the log says "Disenchant recorded".
- [ ] `/cmp dis` lists what you got next to what the table expects.
- [ ] Do 10+ disenchants of the same kind and compare: note anything "not expected".

## History (CueTheCashier_History)

- [ ] After two scans on different days, `/cmp price <item>` shows a 7-day average.
- [ ] Restart the game: the averages are still there.

## Crafting (CueTheCashier_Crafting)

Start with `/cmp debug` on, and have a full scan from today, so most reagents have prices.

Finding professions
- [ ] `/cmp prof`: the log lists every profession you have, each with skill line, level and spells
      (Skinning should show Tanning 1278068, Fishing Bait and Tackle 1278067). Copy it to me.
- [ ] Learn or drop a profession (or train a level): `/cmp prof` again shows the change.

Reading recipes (do this once per profession, including Tanning, Gardening, Smelting and
Bait and Tackle, opened from your spellbook)
- [ ] Open the window: the log says "Recipes read: <name> (<skill line>), N recipes, M known".
- [ ] The log also has one "Recipe info example" and "Recipe schematic example" per profession
      per session. Copy them to me: they show what Forever really returns.
- [ ] `/cmp prof` now says "Recipe window: <spell> (seen opening it)" and "M known of N" for it.
- [ ] Learn a new recipe from a trainer or a recipe item: it gets a profit in the list without /reload.
- [ ] Shift-click someone's profession link (or open the guild's list): prices show, but `/cmp prof`
      does not count those recipes as yours.

Profit in Blizzard's window
- [ ] Recipe list: recipes with prices show the profit at the right of the row, the whole number green
      for a profit, red for a loss, white for none.
      Long recipe names don't run into it. Orange, yellow and green recipes (skill-up arrow) show it too.
- [ ] Scroll and filter the list: the numbers stay on the right recipes.
- [ ] Select a recipe: Craft cost / Sells for / Profit show under the reagents, in Blizzard's font.
      If they overlap something, try `/cmp prof move 0 -20` (x y) and tell me what looks right.
- [ ] Hover those lines: every reagent with its price and "(auction)", "(vendor)" or "(craft)".
- [ ] Check one by hand: e.g. a recipe with thread or vials uses the vendor price when it is cheaper
      than the auction house.
- [ ] A recipe whose reagent you can make yourself (e.g. a bar or a cured hide) shows "(craft)"
      when making it is cheaper.
- [ ] An enchant shows a craft cost and "no auction price", and no number in the list.
- [ ] A recipe with a reagent nobody has scanned shows "(some prices missing)" and "?" profit.
- [ ] Do a scan (or Test Scan) with the window open: the numbers update.

Craft list
- [ ] The **Craft List** button sits left of Create All. If you can't see it, `/cmp prof` writes where it
      is to the log; `/cmp prof button top` moves it to the top right, `/cmp prof button x y` nudges it,
      `/cmp prof button reset` puts it back. `/cmp prof list all` opens the list without the button.
- [ ] Click it: a menu offers "All profitable recipes", "Only <profession>", "Restock items" and "Show the current list".
- [ ] "Only <profession>" lists only that profession's profitable recipes; "All" lists every profession's.
- [ ] The **Crafting List** window opens docked to the right of the profession window and closes with it.
      If you close it by hand it stays closed until the next time you open a profession.
- [ ] Each craft shows a green profit. Left-click a craft: one more. Right-click: one less (0 removes it).
      There are no + and - buttons any more.
- [ ] Crafts are grouped under gold profession titles (open profession first) with the group's profit (0.20.0).
- [ ] Click the title of the open profession: crafts the first recipe of that group you have reagents for.
- [ ] Click another profession's title: exactly that profession's window opens (Cooking opens Cooking,
      Fishing opens Fishing, Skinning opens Skinning; 0.20.0 opened the wrong ones). Click its title again
      to craft; clicking twice never closes the window.
- [ ] `/cmp prof` log: "opened by spell" lines only name the profession's own spells, never a recipe.
- [ ] Manual add (0.22.0): select any recipe you know, also one with a loss. On the Keep in stock line an
      **Add to list** button: click adds 1, Shift-click 5, right-click takes 1 off (Shift: 5). The button
      then reads "On list: N +", and the Crafting List shows it under its profession.
- [ ] At the bottom: total profit and how many reagents you still have to get. **Shopping List** opens the
      second window.
- [ ] A reagent that is cheaper to craft (e.g. a cured hide or a bar) shows as "for reagents" at the top
      of the crafts, and its own reagents are on the Shopping List.
- [ ] With materials in your bags, **Craft** crafts the top recipe the open window can make. Tell me if
      Blizzard blocks it ("Interface action failed") or nothing happens.
- [ ] After a craft finishes, its count goes down by one; the reagent counts follow your bags.
- [ ] The X closes the Crafting List; it is back the next time you open a profession. `/cmp prof list` opens it
      with the same list (also after /reload).

Shopping List (0.19.0)
- [ ] `/cmp prof shop` (or the Shopping List button) opens it. Sections: **Auction House**, **Vendor**,
      **No price yet**, **Mailbox**, **Bank**, **Alts**. Each section only shows when it has something.
- [ ] Auction House and Vendor rows show how many to buy and the cost; "To buy" at the bottom adds up.
- [ ] Hover a row: the item tooltip, plus how many and what to do.
- [ ] Buy Light Leather (or any reagent) on the AH through the Shopping tab: right after the buy it moves
      from Auction House to **Mailbox**. (Buys in Blizzard's own AH window only show once you open the mailbox.)
- [ ] Opens by itself at the auction house, a merchant, the mailbox or the bank when it has something for
      that place, and stays open when you leave. `/cmp prof shop auto` turns that off and on.
- [ ] Ways to open it: right-click the minimap button, Craft List button > **Shopping List**, the
      Shopping List button on the Crafting List, or `/cmp prof shop`. The X closes it.
- [ ] One press of Escape closes everything together, with no "blocked" warning (0.19.4; also with the
      debug log or the ledger open, which close on the same press): at the auction house, Craft Trade, the
      auction house and the Shopping List all close at once; at the mailbox, bank or a merchant the
      Blizzard window and the Shopping List close together.
- [ ] Escape on the profession window closes it and the Crafting List with it, with no "blocked" warning
      (0.19.3 gave SpellStopCasting / SpellStopTargeting blocked).
      `/cmp blocked` then says nothing was blocked.
- [ ] Mailbox open: click a Mailbox row, the mail with that item is taken. Bank open: click a Bank row,
      a stack moves to your bags.
- [ ] Vendor map pins (0.21.0): open a few merchants (general goods, trade suppliers). `/cmp prof vendors`
      lists them in the log with zone and position.
- [ ] Away from merchants, click a Vendor row (e.g. thread or wood): Blizzard's map pin is set on the
      nearest vendor you've seen selling it, and chat says who and where. Right-click always pins.
- [ ] Hover a Vendor row: "Nearest vendor" shows name and zone, or "none seen yet".
- [ ] An item no visited vendor sells says "No vendor selling ... is known yet".
- [ ] At a merchant that sells it, left-click still buys it.
- [ ] Alts rows say which character has it ("Log in on Altname and mail it").

Where materials are (needs a second character on the same server and faction)
- [ ] On the alt, open the bank and the mailbox once, then log back to your crafter: the alt's items
      show under Alts on the Shopping List and are not counted as needed to buy.
- [ ] Mail an item to yourself: once you open the mailbox it shows under Mailbox.
- [ ] A character on another server type or faction is not counted.

Restock
- [ ] Select a recipe: under Craft cost / Sells for / Profit are **Keep in stock** and **Min profit**.
      Enchants (no item) don't show them.
- [ ] Type 5 in Keep in stock (Enter), set Min profit, pick another recipe and come back: the values stayed.
- [ ] Craft List > **Restock items**: lists enough crafts to reach 5, counting all your characters' bags,
      bank and mail. Items you have up for auction are not counted yet.
- [ ] Set Min profit above the recipe's profit: Restock skips it; `/cmp prof restock` says why.
- [ ] Clear Keep in stock (empty or 0): the rule is gone from `/cmp prof restock`.

Shopping (make a Craft List first, with some reagents missing)
- [ ] Auction house > Craft Trade > **Shopping** tab, **Search**: it lists only the reagents the craft list
      marks "auction", with Need (the missing amount), List Price and Max Price (120% of list price).
- [ ] Each row fills in Lowest Buyout, Under Max and Available ("loading" while it looks them up).
- [ ] Click a row: Quantity starts at what you still need (or what your gold pays for). Buy asks first,
      showing your max price and how much under it you pay. Accept: the items arrive.
- [ ] After buying, Need goes down (or the row goes away) without searching again.
- [ ] A reagent with nothing under the max says so and keeps its row.
- [ ] `/cmp prof max 150` raises the max to 150%; Search again shows the new Max Price.
- [ ] With the auction house open, click an Auction House row on the Shopping List: Craft Trade switches to
      the Shopping tab, looks the item up and the buy box pops up for the missing amount. Cancel works.
- [ ] Without the auction house open, the same click says to open it. With a merchant open, clicking a
      vendor reagent asks to buy just that one.
- [ ] Merchant: open a trade supplier that sells a reagent the list marks "vendor" (thread, vials,
      salt...). A **Buy Reagents (N)** button shows at the top right of the merchant window; hover lists
      what and the cost. Click: a box asks; Accept buys exactly the missing amount.
- [ ] Items sold in bundles (e.g. 5 vials for one price) are bought as whole bundles.
- [ ] A merchant with nothing from the list shows no button. `/cmp prof buy` does the same as the button.

Price sources and tooltips
- [ ] Hover an item you can craft (in bags or in the window): the tooltip has a "Craft cost" line.
- [ ] `/cmp sources <that item>` shows craft.cost, craft.value and craft.profit.
- [ ] `/cmp prof top`: the log lists your most profitable known recipes with each reagent's source.

Vendors
- [ ] Visit a trade supplier: with debug on, any reagent whose price differs from the table is
      logged ("Vendor price check"), and `/cmp vendor <item>` gives a buy price for each reagent sold there.

Other characters
- [ ] Log in on a second character with other professions, open their windows, then go back:
      `craft.cost` uses recipes from both characters (crafting a reagent on one for the other).

# Known bugs

Found in game, to look at later (Kim decides when).

- LESSON (25 Nov, 0.40/0.41 rename): Kim's settings, groups, operations and ledger were lost; prices came back
      only from a new scan, history survived. Rules for any future rename or data move: it must be automatic
      (no file steps for the player), and a new empty database must never win over old data. Before shipping,
      test it with a copy of real saved files in every order (old files only, new empty file present, both).
      The in-addon move (CM.AdoptOldSaved) still has the flaw that it won't replace a non-empty fresh DB.
- NEEDS TESTING (Kim has one character, 25 Nov): sending mail to a two-part name. "This character" fills in
  the full name ("Malaeiel Nightwalker"); check that Send Mail reaches that character, and whether a
  first name alone also works.

- Probably fixed by the Escape taint fix in 0.19.6 (Kim, 25 Nov): Shift-click search from a profession
  left the AH item unclickable and X not closing the AH (0.16.0).
- Fixed in 0.17.1, check: recipes with a skill-up arrow (orange, yellow, green) showed no profit in the
  recipe list, only in the details (25 Nov, 0.17.0).
- Craft List button not visible on Forever's profession window (25 Nov, 0.16.0). 0.17.0 raises it above
  the window's art and adds `/cmp prof button top`; check whether that fixes it.

## Name and icons (new in 0.38.0)

- [ ] AddOns list (character select): the suite shows as "CueTheCashier: Maximum Profit" and "CueTheCashier - Accounting" etc., each with the cash register icon.
- [ ] Old saved data is still there: same price count at login, ledger and groups unchanged.
- [ ] Minimap button shows the round cash register icon inside the gold ring, not a question mark.
- [ ] `/cmp` opens the window; the portrait top left is the cash register and the title says CueTheCashier.
- [ ] `/cm` and `/cuethecashier` still work too.
- [ ] Chat lines start with "CueTheCashier:".
- [ ] `/cmp macro`: your old "CraftMarket" macro is renamed to "CueTheCashier" (not a second macro), and it still works with the scroll wheel.

## Crafting List counts what you have (fixed in 0.39.0)

- [ ] Open the Crafting List for a profession, craft everything on it, then open the list again: the items you just made
      are not queued again (bags, bank, mail, your auctions and alts all count).
- [ ] Item with a Crafting operation without Keep in stock: once you have one batch (Most to craft at once), it isn't queued.
- [ ] Sell or mail away the crafted items to someone else, open the list again: they are queued again.

## New folder names (0.40.0)

- [ ] Follow the README steps (delete old CraftMarket folders, rename the five WTF SavedVariables files).
      Log in: same price count as before, ledger, groups and settings all there.
- [ ] Leave an old CraftMarket folder in AddOns on purpose: a red chat line says to delete it.
- [ ] `/cmp status` lists the modules as CueTheCashier_Accounting etc.; modules still load (open the AH, mailbox, a profession).

## Out of the way of other addons (0.40.0)

- [ ] Merchant: Buy Reagents and Sell to Vendor buttons sit at the top right; if another addon (ElvUI, ...) has
      something there, they move just under the merchant window instead. With `/cmp debug` the log says "moved to spot 2".
- [ ] Mailbox and bank buttons: same.
- [ ] Profession window: the Craft List and Make Group buttons don't cover anything (MasterCraft, ElvUI skin).
- [ ] Crafting List: docks right of the profession window; if another addon docks there (e.g. MasterCraft), it docks on the left.
- [ ] `/cmp prof button top` (or x y) still overrides the Craft List button spot by hand.

## Clean names inside (0.41.0)

- [ ] Log in with your data from 0.39/0.40 (WTF files renamed as in the README): prices, ledger, groups, Crafting
      List and disenchant records are all there.
- [ ] Log out and back in: still there (now saved as CueTheCashierDB etc.; open a WTF file and the old
      CraftMarketDB name is gone).
- [ ] Your one-key macro still works with the scroll wheel; chat said "Updated N macro(s)" once.
- [ ] Group text exported from an older version still imports.

## Defaults, lists and craft queue (0.42.0)

Back up your SavedVariables folder first (this version adds Base operations to your profile).

Defaults and Base operations
- [ ] `/cmp` > Operations: every kind has an operation called "Base". Groups > Base Group > Operations shows "Base" for all six.
- [ ] Posting "Base": Undercut by is 0c. Crafting "Base": Lowest profit is `crafting * 30%`, Most to craft at once 1. Vendoring "Base": Sell to vendors is off.
- [ ] An operation you made before 0.42 keeps the values you typed; a field you never touched shows the new default.
- [ ] Delete one Base operation, `/reload`: it doesn't come back.
- [ ] Post Scan with a group that has no Posting operation: its bag items are listed with "Base". Items in no group at all are not listed.
- [ ] Set your Materials group's Posting to "None, not even the Base Group's": Post Scan leaves those items out.
- [ ] Craft List > All profitable: only recipes with profit of at least 30% of the craft cost are queued, one each.

Post Scan
- [ ] Log in fresh, open the AH, run Post Scan once: it lists everything a second scan would (compare the "N to post" of two scans in a row without posting).
- [ ] With `/cmp debug`, the log says "waiting for bag items" on the first scan, and lists items Blizzard says can't be sold (soulbound etc.).
- [ ] Commodity stacks still post as commodities (one price for the stack, "PostCommodity" in the log).

Debug clean-up
- [ ] No Test Scan button next to Full Scan, also with `/cmp debug` on.
- [ ] Full Scan with debug on: the debug log does not open. `/cmp log` opens it.

Crafting List and Shopping List
- [ ] Queue a few recipes, right-click one row a few times, left-click another: no rows change place.
- [ ] Drag the Crafting List somewhere, close and open the profession window (and another profession): it opens at the same spot next to the window. `/cmp prof dock` puts it back.
- [ ] Without a saved spot: with your profession tab bar showing, the list opens right of the tab bar, not over it.
      With `/cmp debug` the log says "Crafting List moved to spot 2" (or 3).
- [ ] Drag the Shopping List, close it, open it again: same spot.
- [ ] Shopping List shows names for all reagents (not "item 1234"). An unknown one turns into a name within a second.

Not enough on the auction house (needs a full scan made with 0.42.0)
- [ ] Shift-click Add to list a few times on a recipe whose reagent is scarce on the AH: a box asks "None / Only N / All M".
      None = back to what it was, Only N = N on the list, All = as asked (and no more asking for it until Clear).
- [ ] Craft List > All profitable with a scarce reagent: one box for all short recipes: "None of them / What's for sale / All".
- [ ] The numbers look right compared to what the Buy tab shows under your top price (rounded down to price steps of 10%, 20%, 35%, 50%, 100%, 200% over the cheapest).

Craft timer
- [ ] Create All (or our Craft button) for 5+ of something: the cast bar shows `00:03/00:15` style text at its right, counting up; the total is right after the first cast.
- [ ] Move to interrupt: the timer goes away. Finish the batch: it goes away.
- [ ] With another addon's cast bar (Blizzard's hidden), the text shows alone above the bottom middle of the screen as "Crafting 2/5 00:03/00:15".

Groups and bank
- [ ] Groups tab, a long item list: scroll down, click an item (or Add/Remove): the list stays where it was. Picking another group starts at the top.
- [ ] Bank: Bank Moves sits bottom right, right of Purchase and above the gold, not over the search box.

## Fixes after Kim's 0.42.0 test (0.42.1)

- [ ] Post Scan lists every sellable item in your bags (Earthroot, skinning knife...), grouped or not, with "Base".
      A group set to Posting "None, not even the Base Group's" keeps its items out. Soulbound items stay out.
- [ ] Drag the Crafting List, close the profession window, open it (and another profession), `/reload`: it opens at your spot.
      The log (`/cmp log`) says "Crafting List spot saved: x, y". `/cmp prof dock` puts it back next to the window.
- [ ] After `/cmp prof dock`: the list starts right of the profession tab buttons, not over them. With `/cmp debug`
      the log says "Crafting List docked N right of the profession window (... things on its right edge)".
- [ ] Groups: make Leatherworking > Armor and put an item in Armor. In Leatherworking's list that item is grey with
      "in Armor" on the right. In another sub-group's left list it shows "in Armor" too.
- [ ] Crafting List, Shopping List, `/cmp log`, `/cmp destroy` and the "how many to queue" box look like the auction
      house window: same border, title and background, list on a dark inset, striped rows. No portrait circle
      (if one shows with our icon, the content should start below it).
- [ ] Settings > Skin > Dark, `/reload`: those windows follow the skin too.

## Queue from groups (0.42.2)

- [ ] Crafting List: the third button says "Queue...". Right-click it: Shopping List opens.
- [ ] Click it: a window lists your groups (sub-groups indented) with tick boxes, and "Everything" on top.
- [ ] Tick Cooking only, Queue: the list holds only profitable Cooking recipes (whose result is in Cooking or its sub-groups).
- [ ] Tick Everything: the groups grey out; Queue queues every profitable recipe you know.
- [ ] Close and open the window: your ticks are still there (also after `/reload`).
- [ ] If a reagent is short on the AH, the "None of them / What's for sale / All" box follows.

## Send Mail arrow (0.42.3)

- [ ] Mailbox > Send Mail: no big Send Mail button; a small down arrow sits right of the To: box (left of Postage).
- [ ] Click it: Send by Mailing operations (n), then Alts, Recently mailed, Friends, Guild. Hover the first line: what goes to whom.
- [ ] Pick an alt: To: gets the full name (log that alt in once with 0.42.3 so its surname is known), the cursor moves to Subject.
- [ ] Send a mail by hand to someone, open the menu again: they are first under Recently mailed.
- [ ] Send by Mailing operations sends like the old button did. The Inbox tab still shows Open Mail.

## Lists keep their place (0.42.4)

- [ ] Operations tab: scroll the list down, click an operation: the list stays put.
- [ ] Same in Prices (custom prices and sources), Ledger, Inventory, Groups (tree and both item lists).
- [ ] AH: Buy results, Auctions, Post, Shopping, Snipe and the item page keep their spot when they refresh.

