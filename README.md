# macOS Login, Startup and User Profile Troubleshooter

A macOS support toolkit for diagnosing and repairing common login, startup-item and user-profile problems.

## Diagnostic script

```bash
chmod +x src/login_profile_troubleshooter.sh
./src/login_profile_troubleshooter.sh --hours 24
```

The diagnostic script checks login and background items, LaunchAgents and LaunchDaemons, home-folder ownership and storage, startup indicators, console-user information and recent profile events.

## Repair script

Preview the standard repair:

```bash
chmod +x src/login_profile_repair.sh
./src/login_profile_repair.sh --repair --dry-run
```

Apply the standard repair:

```bash
./src/login_profile_repair.sh --repair
```

Reset standard user permissions:

```bash
./src/login_profile_repair.sh --reset-user-permissions
```

Rebuild Launch Services registration:

```bash
./src/login_profile_repair.sh --rebuild-launchservices
```

Back up and disable one user LaunchAgent:

```bash
./src/login_profile_repair.sh \
  --disable-agent "$HOME/Library/LaunchAgents/com.example.agent.plist"
```

## What the repair does

- Restarts user preference, background-item and login helper processes.
- Can run `diskutil resetUserPermissions` for the selected user.
- Can rebuild Launch Services application registration.
- Can validate, unload, back up and disable one user LaunchAgent.
- Supports dry-run, confirmation controls, backups, logging and post-repair verification.
- Returns clear success, warning and invalid-argument exit codes.

## Safety and limitations

The tool does not delete the user profile or remove documents. LaunchAgents are moved into the report backup folder instead of being deleted. Permission repair is limited to the supported `diskutil` operation. Problems caused by damaged user databases, FileVault issues or unavailable network accounts may require separate investigation.

## Author

Dewald Pretorius — L2 IT Support Engineer
