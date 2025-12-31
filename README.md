# modhousekeeper

A norns mod manager for the installation, updating, and removal of mods.

## Features

- Browse available mods organized by category
- Visual indicators for installation status
- Supports local mods not defined by modhousekeeper's mods.list
- Install mods with a single action
- Check for and install updates
- Remove installed mods
- Supports local mod lists
- Support alternative versions of mods that are in a different repository or a branch (useful when testing new features)
- Fancy starting animation (based on Tobias V. Langhoff's tweetcart) that can be bypassed or disabled from settings

## Installation

1. Install modhousekeeper in Maiden:
   ```
   ;install https://github.com/vehka/modhousekeeper.git
   ```

2. Enable the mod:
   - Navigate to SYSTEM > MODS on your Norns
   - Enable "modhousekeeper" by turning encoder three clockwise
   - Restart Norns

## Usage

### Opening the mod manager

From your Norns hardware:
1. Navigate to **SYSTEM > MODS**
2. Select **"modhousekeeper"** and press button three

### Controls

**Mod List:**

- **E2** (Encoder 2): Scroll through list
- **K2** (Key 2): Exit to mods menu
- **K3** (Key 3): Open action menu (on mods) / Enter settings (on ▦ Settings)

**Action Menu:**

- **E2** (Encoder 2): Navigate menu options
- **K2** (Key 2): Close menu
- **K3** (Key 3): Execute selected action

**Settings:**

- **E2** (Encoder 2): Navigate settings
- **E3** (Encoder 3): Toggle setting value
- **K2** (Key 2): Return to mod list

### Action Menu

Press **K3** on any mod to open its action menu, which shows:

- **Mod description** - Brief info about the mod
- **Primary actions** - Install, Update (if available), or Remove
- **Alternative repos** - Install from development branches or different repositories (if available)

Each alternative repository entry includes a description, defined in the main mod list (see below).

### Status Indicators

- **○** : Mod not installed
- **◉** : Mod installed
- **◆** : Update available

### Settings

Access the settings screen by scrolling to **▦ Settings** at the top of the mod list and pressing **K3**. Available settings:

- **Disable start animation**: Disable the startup animation (feature not yet implemented)
- **Use local mods.list**: When enabled, uses `mods.list.local` instead of `mods.list`
  - This prevents git merge conflicts when pulling updates to modhousekeeper
  - The first time you enable this, a local copy is automatically created
  - You can then customize your local list without affecting the main file

### Adding Mods to the List

Edit `mods.list` in the ModHousekeeper directory:

```
# Category Name

ModName, https://github.com/username/modname, Brief description of the mod
AnotherMod, https://github.com/username/another, Description here, https://github.com/fork/another, Fork with extra features

# Another Category

ThirdMod, https://github.com/username/third, "Description of third mod, with nifty features, commas in description require double quotes"
```

**Format:**
- Category headers start with `#`
- Mod entries: `ModName, GitURL, Description [, alt_url1, alt_desc1, alt_url2, alt_desc2, ...]`
  - **Name** (required): Display name
  - **URL** (required): Primary GitHub repository
  - **Description** (required): Brief one-line description
  - **Alternative repos** (optional): Pairs of URL and description for development branches, forks, etc.
  - **Quoting**: Use double quotes around any field containing commas (e.g., `"description with, commas"`)
- Empty lines are ignored

## Version History

### v1.0.0
- Initial release
- Basic install/update/remove functionality
- Category organization
- Update checking

## GenAI disclaimer

* Co-created with Claude 4.5 Sonnet and Opus