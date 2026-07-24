# Disabling Logi Options+ (reversible)

LogiOptions needs exclusive HID++ access. Stop official Options+ agents before use.

## Stop (user session)

```bash
./tools/stop_options_plus.sh
```

What it does:

1. `launchctl bootout` for Options+ LaunchAgents in the GUI domain  
2. Kills residual `logioptionsplus*` / `logioptionsplus_agent` processes  
3. Leaves the app on disk (easy to re-enable)

## Re-enable

```bash
./tools/start_options_plus.sh
```

## Manual checklist

```bash
# Agents
launchctl bootout gui/$(id -u) /Library/LaunchAgents/com.logi.optionsplus.plist 2>/dev/null
launchctl bootout gui/$(id -u) /Library/LaunchAgents/com.logi.optionsplus.logivoice.plist 2>/dev/null

# Verify gone
pgrep -lf logioptionsplus || echo "clean"
```

**Note:** The updater may run as root (`com.logi.optionsplus.updater`). Booting it out needs admin:

```bash
sudo launchctl bootout system /Library/LaunchDaemons/com.logi.optionsplus.updater.plist
```

For daily driving LogiOptions, stopping the user agent is enough.

## Uninstall (optional, heavier)

Use Logitech’s uninstaller if present, or remove:

- `/Applications/logioptionsplus.app`
- `/Library/Application Support/Logitech.localized/LogiOptionsPlus`
- LaunchAgents / LaunchDaemons listed above  
- `~/Library/Application Support/LogiOptionsPlus` (settings)

Prefer stop-only until LogiOptions is proven.
