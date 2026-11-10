<p align="center"><img src="assets/logo.png" width="256" alt="Mirra's Poisons"></p>

# Mirra's Poisons

A lightweight WoW Forever addon for rogues: it shows you when a weapon has no poison and applies a poison from your bags to your main hand or off hand with a single click.

## Features

- **Pops up when you need it:** as soon as your main hand or off hand has no poison, a compact tracker appears with the weapon icon (pulsing red frame) and every poison you carry
- **One click to apply:** each poison button applies that poison to the hand of its row (`/use item` + `/use 16` / `/use 17`), no dragging, no cursor targeting
- **Reads your bags automatically:** shows the highest rank of every poison type you carry (Instant, Deadly, Wound, Crippling, Mind-numbing), with stack count and rank. New ranks are recognised by name
- **Remembers your choice:** the poison you last used on a hand gets a gold frame
- Only real weapons count: shields, off-hand items and fishing poles are ignored
- Poison name, remaining time and charges next to each weapon (optional)
- **Warn early (optional):** also show the tracker when less than N minutes or N charges are left
- **Alerts:** raid warning sound and text when a poison runs out
- Confirms the "replace enchant" question for you when you click a poison over an old one (optional)
- Hide in cities and inns, hide while you carry no poisons
- Modes: only when needed, or always (both weapons with status)
- Adjustable icon size and scale, movable tracker
- Settings panel with live preview under **Options → AddOns → Mirra's Poisons**
- Works with WoW Forever secret values (Interface 16001); in combat the last known state is kept when the client hides the values
- Language independent: poison names are read from the game client

## Combat

Blizzard does not allow addons to show, hide or change click buttons in combat. If the tracker is already visible when combat starts, its buttons keep working. If a poison runs out during combat, a red "No poison: Main Hand" warning appears at the tracker position instead, and the buttons appear as soon as combat ends.

## Installation

Copy the addon into your WoW Forever `Interface/AddOns/MirraPoisons/` folder
(the folder must be named `MirraPoisons`, matching `MirraPoisons.toc`).

## Commands

| Command           | Description                         |
|-------------------|-------------------------------------|
| `/mpoison`        | Open the settings                   |
| `/mpoison unlock` | Unlock the tracker to drag it       |
| `/mpoison lock`   | Lock the tracker                    |
| `/mpoison reset`  | Reset the tracker position          |
| `/mpoison debug`  | Print debug information             |
