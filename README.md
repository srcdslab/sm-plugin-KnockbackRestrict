> [!IMPORTANT]
> If using KbRestrict with Zombie:Reloaded, **you need** to use ZR minimum version [3.12.16](https://github.com/srcdslab/sm-plugin-zombiereloaded/releases) or newest.

> [!WARNING]
> For versions 3.4.0 and 3.5.0: If you are using an older version of the plugin, please perform the migration by [following the provided steps](#migration).

You can find the web panel [here](https://github.com/srcdslab/kbans-web)

# Migration
## 3.3.4 to 3.4.0

You need to run the following queries:

### MYSQL
```sql
ALTER TABLE `KbRestrict_CurrentBans`
    MODIFY COLUMN `client_name` varchar(128) NOT NULL,
    MODIFY COLUMN `client_steamid` varchar(64) NOT NULL,
    MODIFY COLUMN `client_ip` varchar(16) NOT NULL,
    MODIFY COLUMN `admin_name` varchar(128) NOT NULL,
    MODIFY COLUMN `admin_steamid` varchar(64) NOT NULL,
    MODIFY COLUMN `reason` varchar(128) NOT NULL,
    MODIFY COLUMN `map` varchar(256) NOT NULL,
    MODIFY COLUMN `admin_name_removed` varchar(128) NOT NULL,
    MODIFY COLUMN `admin_steamid_removed` varchar(64) NOT NULL,
    MODIFY COLUMN `reason_removed` varchar(128) NOT NULL;

ALTER TABLE `KbRestrict_srvlogs`
    MODIFY COLUMN `admin_name` varchar(128) NOT NULL,
    MODIFY COLUMN `admin_steamid` varchar(64) NOT NULL,
    MODIFY COLUMN `client_name` varchar(128) NOT NULL,
    MODIFY COLUMN `client_steamid` varchar(64) NOT NULL;

ALTER TABLE `KbRestrict_weblogs`
    MODIFY COLUMN `admin_name` varchar(128) NOT NULL,
    MODIFY COLUMN `admin_steamid` varchar(64) NOT NULL,
    MODIFY COLUMN `client_name` varchar(128) NOT NULL,
    MODIFY COLUMN `client_steamid` varchar(64) NOT NULL;

OPTIMIZE TABLE `KbRestrict_CurrentBans`;
OPTIMIZE TABLE `KbRestrict_srvlogs`;
OPTIMIZE TABLE `KbRestrict_weblogs`;
```

## 3.4.11 to 3.5.0

### MYSQL
```sql
CREATE INDEX IF NOT EXISTS `idx_steamid_search` ON `KbRestrict_CurrentBans` (`client_steamid`);
CREATE INDEX IF NOT EXISTS `idx_ip_search` ON `KbRestrict_CurrentBans` (`client_ip`);
CREATE INDEX IF NOT EXISTS `idx_admin_steamid` ON `KbRestrict_CurrentBans` (`admin_steamid`);
CREATE INDEX IF NOT EXISTS `idx_expiry_sort` ON `KbRestrict_CurrentBans` (`time_stamp_start`, `time_stamp_end`);
CREATE INDEX IF NOT EXISTS `idx_status` ON `KbRestrict_CurrentBans` (`is_expired`, `is_removed`);
CREATE INDEX IF NOT EXISTS `idx_steamid_ip_status` ON `KbRestrict_CurrentBans` (`client_steamid`, `client_ip`, `is_expired`, `is_removed`);
OPTIMIZE TABLE `KbRestrict_CurrentBans`;
```
