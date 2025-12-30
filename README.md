# modhousekeeper

A Norns mod manager for the installation, updating, and removal of mods.

## Features

- Browse available mods organized by category
- Visual indicators for installation status
- Install mods with a single action
- Check for and install updates
- Remove installed mods

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

**While browsing mods:**

- **E2** (Encoder 2): Scroll through mod list
- **E3 Right** (Encoder 3 clockwise): Show install/update confirmation
- **E3 Left** (Encoder 3 counter-clockwise): Show remove confirmation
- **K2** (Key 2): Exit back to mods menu
- **K3** (Key 3): Quick install/update (shows confirmation)

### Status Indicators

- **-** : Mod not installed
- **\*** : Mod installed
- **U** : Update available

### Adding Mods to the List

Edit `mods.list` in the ModHousekeeper directory:

```
# Category Name
ModName, https://github.com/username/modname, Brief description of the mod
AnotherMod, https://github.com/username/another, Description here, https://github.com/fork/another

# Another Category
ThirdMod, https://github.com/username/third, Description of third mod
```

**Format:**
- Category headers start with `#`
- Mod entries: `ModName, GitURL, Description [, alt_url1, alt_url2, ...]`
  - **Name** (required): Display name
  - **URL** (required): Primary GitHub repository
  - **Description** (required): Brief one-line description
  - **Alternative URLs** (optional): Development branches, forks, etc.
- Empty lines and comments are ignored
## Version History

### v1.0.0
- Initial release
- Basic install/update/remove functionality
- Category organization
- Update checking

