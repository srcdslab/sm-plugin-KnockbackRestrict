# GitHub Copilot Instructions for KnockbackRestrict

## Repository Overview

This repository contains **KnockbackRestrict**, a SourceMod plugin for Source engine games that manages knockback restrictions for players. The plugin provides a comprehensive ban system that reduces weapon knockback for restricted players while maintaining full database persistence and web panel integration.

**Primary Purpose**: Restrict player knockback as a form of punishment/moderation tool for Source engine game servers.

## Technical Environment

- **Language**: SourcePawn (SourceMod scripting language)
- **Platform**: SourceMod 1.11+ (minimum version specified in sourceknight.yaml)
- **Compiler**: SourcePawn compiler (spcomp) via SourceKnight build system
- **Database**: MySQL with UTF8MB4 charset and unicode collation
- **Dependencies**: MultiColors, KnifeMode (optional), ZombieReloaded (optional)

## Project Structure

```
├── addons/sourcemod/
│   ├── scripting/
│   │   ├── KnockbackRestrict.sp          # Main plugin file (~1900 lines)
│   │   ├── helpers/
│   │   │   └── menus.sp                  # Admin menu implementation
│   │   └── include/
│   │       └── KnockbackRestrict.inc     # Native functions and forwards
│   └── translations/
│       └── knockbackrestrict.phrases.txt # Translation file
├── .github/workflows/ci.yml              # CI/CD configuration
├── sourceknight.yaml                     # Build configuration
└── README.md                            # Documentation with migration scripts
```

## Key Components

### 1. Main Plugin (`KnockbackRestrict.sp`)
- **Core functionality**: Ban/unban system, knockback reduction, database operations
- **Key features**: Online/offline player management, admin commands, event handling
- **Database operations**: All SQL queries are asynchronous using methodmaps
- **Memory management**: Uses proper `delete` calls, StringMap/ArrayList handling

### 2. Include File (`KnockbackRestrict.inc`)
- **Native functions**: `KR_BanClient`, `KR_UnBanClient`, `KR_ClientStatus`, etc.
- **Forwards**: `KR_OnClientKbanned`, `KR_OnClientKunbanned`
- **Version**: Current version is 4.0.2 (defined as constants)

### 3. Helper Modules (`helpers/menus.sp`)
- **Admin menu integration**: TopMenu implementation for SourceMod admin interface
- **Menu handlers**: Category and item handlers for admin commands

## Build System & Dependencies

### SourceKnight Configuration
The project uses **SourceKnight 0.2** for automated building:

```yaml
# sourceknight.yaml defines:
- SourceMod 1.11.0-git6934 (main dependency)
- MultiColors (for colored chat messages)
- KnifeMode (optional, for knife-specific features)  
- ZombieReloaded (optional, for zombie mod integration)
```

### Building the Plugin
1. **CI/CD**: GitHub Actions automatically builds on push/PR using `maxime1907/action-sourceknight@v1`
2. **Local Building**: Use SourceKnight CLI: `sourceknight build`
3. **Output**: Compiled `.smx` files go to `/addons/sourcemod/plugins`

### Dependencies Management
- External includes are automatically downloaded during build
- Version pinning ensures consistent builds
- Optional dependencies use `#tryinclude` to prevent build failures

## Database Schema

### Tables
- `KbRestrict_CurrentBans`: Active ban records with indexed columns for performance
- `KbRestrict_srvlogs`: Server-side ban/unban logs  
- `KbRestrict_weblogs`: Web panel action logs

### Migration Requirements
- **Version 3.3.4 → 3.4.0**: Column size adjustments for names, SteamIDs, reasons
- **Version 3.4.11 → 3.5.0**: Performance indexes for searches and sorting
- Always include `OPTIMIZE TABLE` after schema changes

## Code Style & Standards

### SourcePawn Conventions
```sourcepawn
#pragma semicolon 1
#pragma newdecls required

// Variable naming
int g_iGlobalVariable;              // Prefix globals with g_, use Hungarian notation
bool g_bIsClientRestricted[MAXPLAYERS + 1];
char g_sClientName[MAXPLAYERS + 1][MAX_NAME_LENGTH];

// Function naming
public void OnPluginStart()         // PascalCase for public functions
void DoSomethingInternal()         // PascalCase for internal functions
```

### Database Operations
```sourcepawn
// ✅ ALWAYS use async queries with methodmaps
Database.Connect(ConnectCallback, "database_name");

// ✅ Proper prepared statements to prevent SQL injection
char sQuery[512];
hDB.Format(sQuery, sizeof(sQuery), "SELECT * FROM table WHERE steamid = '%s'", sSteamID);
hDB.Query(QueryCallback, sQuery);

// ✅ Use transactions for related operations
Transaction txn = new Transaction();
txn.AddQuery("INSERT INTO...");
txn.AddQuery("UPDATE...");
hDB.Execute(txn, TransactionSuccess, TransactionFailure);
```

### Memory Management
```sourcepawn
// ✅ Direct delete without null checks
delete g_hStringMap;
g_hStringMap = new StringMap();

// ❌ NEVER use .Clear() on StringMap/ArrayList (causes memory leaks)
// ✅ Always delete and recreate instead
delete g_hArrayList;
g_hArrayList = new ArrayList();
```

## Development Workflow

### Making Changes
1. **Understand the impact**: This plugin integrates with other mods (ZR, KnifeMode)
2. **Database considerations**: Changes may require migration scripts
3. **Translation updates**: Add new phrases to `knockbackrestrict.phrases.txt`
4. **Version bumping**: Update constants in `KnockbackRestrict.inc`

### Testing Approach
- **Local testing**: Use SourceMod development server
- **Database testing**: Verify async operations don't block server
- **Integration testing**: Test with ZombieReloaded and KnifeMode when present
- **Performance testing**: Monitor server tick rate impact

### Code Review Focus Areas
1. **SQL injection prevention**: All user input must be properly escaped
2. **Memory leaks**: Verify proper `delete` usage for handles
3. **Async operations**: Database queries must not block the main thread
4. **Client validation**: Always verify client indexes and connection status
5. **Translation coverage**: All user messages should use translation system

## Commands & Permissions

### Admin Commands
- `sm_kban <player> <time> [reason]` - ADMFLAG_KICK
- `sm_kunban <player> [reason]` - ADMFLAG_KICK  
- `sm_koban <steamid> <time> [reason]` - ADMFLAG_KICK (offline bans)
- `sm_kbanlist` - ADMFLAG_KICK (view ban list)

### Console Commands
- `sm_kstatus` / `sm_kbstatus` / `sm_kbanstatus` - Check personal status

### ConVars (Key Settings)
- `sm_kbrestrict_length "30"` - Default ban length
- `sm_kbrestrict_max_bantime_*` - Maximum ban times per admin flag
- `sm_kbrestrict_reduce_*` - Knockback reduction values per weapon type
- `sm_kbrestrict_display_connect_msg "1"` - Show connect message to banned players

## Integration Points

### Plugin Dependencies
- **Optional**: KnifeMode integration for reduced knife knockback in knife rounds
- **Optional**: ZombieReloaded integration (requires ZR 3.12.16+)
- **Required**: MultiColors for formatted chat messages

### Native Functions (for other plugins)
```sourcepawn
// Check if player is knockback banned
bool KR_ClientStatus(int client);

// Get number of active bans for player  
int KR_GetClientKbansNumber(int client);

// Programmatically ban/unban players
KR_BanClient(int admin, int target, int time, const char[] reason);
KR_UnBanClient(int admin, int target, char[] reason);
```

### Forward Events
```sourcepawn
// Called when player gets knockback banned
forward void KR_OnClientKbanned(int client, int admin, int length, const char[] reason, int kbansNumber);

// Called when player's knockback ban is removed
forward void KR_OnClientKunbanned(int client, int admin, const char[] reason, int kbansNumber);
```

## Performance Considerations

### Database Optimization
- Indexed columns for fast lookups: `client_steamid`, `client_ip`, `admin_steamid`
- Composite indexes for complex queries: `steamid + ip + status`
- Regular `OPTIMIZE TABLE` maintenance after bulk operations

### Runtime Performance  
- **Client data caching**: Steam IDs, IPs cached on connect to avoid repeated queries
- **Batch operations**: Use transactions for multiple related database operations
- **Efficient weapon detection**: Weapon-specific knockback reduction using game events
- **Memory optimization**: Proper cleanup of handles and data structures

## Deployment & Releases

### Version Management
- **Semantic versioning**: MAJOR.MINOR.PATCH format
- **Version constants**: Defined in `KnockbackRestrict.inc`
- **Git tags**: Automated by CI/CD on version changes

### Release Process
1. **Automated builds**: GitHub Actions compiles and packages plugin
2. **Artifact generation**: Creates `.tar.gz` with plugin files and translations
3. **Release creation**: Automatic GitHub releases with downloadable packages
4. **Latest tag**: Always points to most recent stable build

### Migration Checklist
When updating from older versions:
1. **Backup database** before running migration scripts
2. **Run SQL migrations** as documented in README.md
3. **Update plugin files** and restart server
4. **Verify functionality** with test bans/unbans
5. **Check web panel compatibility** if using external panel

## Troubleshooting Common Issues

### Build Failures
- **Missing dependencies**: Check sourceknight.yaml dependency versions
- **Include errors**: Verify all required `.inc` files are accessible
- **Syntax errors**: Follow SourcePawn conventions and pragmas

### Runtime Issues
- **Database connection failures**: Check database credentials and accessibility
- **Permission errors**: Verify admin flags match command requirements  
- **Plugin conflicts**: Check load order with ZombieReloaded and KnifeMode
- **Memory leaks**: Review StringMap/ArrayList usage and delete patterns

### Database Issues
- **Performance problems**: Run migration scripts to add missing indexes
- **Character encoding**: Ensure UTF8MB4 charset and unicode collation
- **Connection timeouts**: Use connection pooling and async queries only

## Quick Reference

### Important Files to Modify
- **Core logic**: `addons/sourcemod/scripting/KnockbackRestrict.sp`
- **API interface**: `addons/sourcemod/scripting/include/KnockbackRestrict.inc`  
- **Admin menus**: `addons/sourcemod/scripting/helpers/menus.sp`
- **User messages**: `addons/sourcemod/translations/knockbackrestrict.phrases.txt`
- **Build config**: `sourceknight.yaml`

### Key Constants & Limits
- `MAX_NAME_LENGTH`: Player name limit
- `MAX_AUTHID_LENGTH`: SteamID string limit  
- `REASON_MAX_LENGTH`: Ban reason limit (128 chars)
- `MAX_IP_LENGTH`: IP address string limit (16 chars)
- `MAX_QUERIE_LENGTH`: SQL query buffer size (2000 chars)

### Testing Commands
```bash
# Build plugin locally (requires SourceKnight)
sourceknight build

# Check syntax without full build
spcomp -i/path/to/includes KnockbackRestrict.sp

# Database testing queries
SELECT COUNT(*) FROM KbRestrict_CurrentBans WHERE is_expired = 0;
```

This plugin is mission-critical for server moderation - always test changes thoroughly in a development environment before deploying to production servers.