# macOS Login, Startup and User Profile Troubleshooter

A read-only Bash toolkit for collecting login items, background items, launch agents, home-folder permissions, user profile storage, cache size, startup state, and recent login-window evidence.

## Usage

```bash
chmod +x src/login_profile_troubleshooter.sh
./src/login_profile_troubleshooter.sh --hours 24
```

## Checks performed

- Login and background items
- User and system LaunchAgents and LaunchDaemons
- Home-folder ownership, permissions, and free space
- User cache and preference storage sizes
- Current console user, shell, and login history
- Safe-mode and startup indicators
- Recent loginwindow, launchservices, background-task, and profile events
- Text, CSV, and JSON reports

## Safety

The script does not remove login items, clear caches, reset preferences, change permissions, disable extensions, or modify the user profile.

## Author

Dewald Pretorius — L2 IT Support Engineer
