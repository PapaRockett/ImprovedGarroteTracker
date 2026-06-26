# Improved Garrote Tracker

A passive World of Warcraft Retail/Midnight addon for Assassination Rogues.

The addon tracks whether your Garrote applications or refreshes were made while
Improved Garrote was active. Improved Garrote is a player buff/window, not a
separate target debuff, so the addon records the target GUID at the time your
combat log reports a Garrote application or refresh.

## Safety model

Version 3.0 is intentionally passive:

- listens to events only;
- stores state in addon-owned Lua tables;
- creates one fixed, non-interactive, non-secure text display frame parented to `UIParent`;
- does not create `SecureActionButtonTemplate` frames;
- does not call protected action APIs;
- does not modify Blizzard nameplate aura buttons, action bars, raid frames,
  party frames, Edit Mode, or protected unit-frame internals.

## Commands

- `/igt status` - print the current target GUID and tracked Improved Garrote state.
- `/igt debug on` - enable debug prints.
- `/igt debug off` - disable debug prints.

## Crimson Tempest inference

If you cast Crimson Tempest while at least one tracked Improved Garrote is
active, Garrote applications or refreshes by you during a short configurable
window are treated as improved. The default window is `0.5` seconds.
