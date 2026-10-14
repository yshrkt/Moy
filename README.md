<img src="docs/Images/AppIcon.png" alt="Moy app icon" width="128">

# Moy

**A safe harbor for your local services.**

Moy is a macOS menu bar app for registering and managing command-line services as LaunchAgents / LaunchDaemons. Manage your services from the menu bar or the bundled `moy` CLI.

[日本語](README.ja.md)

<img src="docs/Images/Screenshot.jpg" alt="Moy menu bar showing service statuses and controls" width="400">

## Requirements

- macOS 26 or later (Apple Silicon only).
- Xcode 27 / Swift 6.4
- mise

## Build

Run these commands to build and launch the app.

```bash
mise install
mise run generate
mise run build
open build/Build/Products/Debug/Moy.app
```

## Features

- Add, edit, enable, disable, and restart services.
- Check service status and open stdout/stderr logs from the menu bar.
- Share service definitions between the GUI and CLI, with JSON output for scripts.

- Manage LaunchAgents / LaunchDaemons registered through Moy.
- Keep services managed by `launchd` after quitting Moy.

## Usage

Open `Moy.app` and use the menu bar to manage services.

1. Choose **Manage Services…** and add a service.
2. Choose the service kind, enter a unique identifier and the absolute executable path, then configure arguments and environment variables.
3. Save the definition, then enable it from the service details when needed.

Service actions work as follows.

| Action | Behavior |
| --- | --- |
| Enable | Create the service plist and load it into `launchd`. |
| Disable | Stop and unload the service, then remove its plist. Keep the definition and logs. |
| Restart | Start a waiting service or restart a running one. Requires an enabled, loaded service. |
| Remove | Disable the service and delete its definition. Keep logs. |

- Enabled LaunchAgents are loaded again at login; LaunchDaemons are loaded at system startup.
- Automatic startup depends on `RunAtLoad` and `KeepAlive`.

LaunchDaemon changes require administrator authentication in the GUI or `sudo` in the CLI.

### Service settings

Moy supports the following launchd settings.

| Setting | Purpose |
| --- | --- |
| `Label` | Generated as `com.sputnik-apps.moy.<Identifier>`. Identifier is immutable after creation. |
| `ProgramArguments` | Absolute executable path followed by ordered arguments. |
| `WorkingDirectory` | Optional working directory. |
| `EnvironmentVariables` | Environment variables passed to the process. |
| `RunAtLoad` | Start when the service is loaded. Off by default. |
| `KeepAlive` | Start and keep the service running. Off by default. |
| `ThrottleInterval` | Minimum interval between launches, in seconds. Uses the OS default if omitted. |
| `StandardOutPath` / `StandardErrorPath` | Log paths. Use Moy’s log directory if omitted. |

- Identifiers use 1–64 lowercase ASCII letters, digits, hyphens, or underscores, starting and ending with a letter or digit.
- Use an absolute executable path.
- Shell configuration is not loaded. Set required environment variables explicitly, including `PATH` when needed.
- Each GUI argument row is one literal argument. Quotes and `$VARIABLE` are passed unchanged.
- For shell logic, pass a script as an argument to an executable such as `/bin/zsh`.
- `ThrottleInterval` limits launch frequency; it does not schedule jobs.

### CLI

#### Install or uninstall

- Open **Settings… → Command Line Tool** to create or remove the bundled CLI’s symbolic link at `/usr/local/bin/moy`.
- macOS asks for administrator authentication only when needed.
- Existing files and unrelated links are never overwritten.
- Uninstalling removes only the link. Services, settings, and logs remain.

#### Example

This example registers a web server, checks its status, and restarts it.

```bash
moy --help

# Save a service definition, then enable it.
moy add --identifier web-server \
  --name "Local web server" \
  --program /usr/bin/python3 \
  --arg -m --arg http.server --arg 8080 \
  --working-directory "$PWD" \
  --run-at-load

moy enable web-server
moy status web-server
moy restart web-server
moy logs web-server
moy disable web-server
```

#### Subcommands

The following subcommands are available.

| Command | Behavior |
| --- | --- |
| `list` | List registered services. |
| `show` | Show a service definition. |
| `add` | Add a service definition. |
| `edit` | Update service settings. |
| `import` | Import a service from a JSON file. |
| `export` | Export a service to a JSON file. |
| `remove` | Disable the service and delete its definition. |
| `enable` | Create the plist and enable the service. |
| `disable` | Stop and unload the service, then remove its plist. |
| `restart` | Start a waiting service or restart a running one. |
| `status` | Show service status. |
| `logs` | Show stdout and stderr log file paths. |

- Use identifiers to specify services.
- `add --enable` saves and enables in one step.
- `status` shows all services when the identifier is omitted.
- `list`, `show`, `status`, and `logs` support `--json` output.
- See `moy <command> --help` for each command’s options.

## License

[MIT](LICENSE) © 2026 Yoshihiro Kato
