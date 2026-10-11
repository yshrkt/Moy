# Moy

**A safe harbor for your local services.**

Moy is a macOS menu bar app for registering and managing command-line services as user LaunchAgents. Manage your services from the menu bar or the bundled `moy` CLI.

[日本語](README.ja.md)

## Requirements

- macOS 26 or later.
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

- Manage user LaunchAgents registered through Moy.
- Keep services managed by `launchd` after quitting Moy.

## Usage

Open `Moy.app` and use the menu bar to manage services.

1. Choose **Manage Services…** and add a service.
2. Enter a unique identifier and the absolute executable path, then configure arguments and environment variables.
3. Save the definition, or save and enable it immediately.

Service actions work as follows.

| Action | Behavior |
| --- | --- |
| Enable | Create the LaunchAgent plist and load it into `launchd`. |
| Disable | Stop and unload the service, then remove its plist. Keep the definition and logs. |
| Restart | Start a waiting service or restart a running one. Requires an enabled, loaded service. |
| Remove | Disable the service and delete its definition. Keep logs. |

- Enabled services are loaded again at login.
- Automatic startup depends on `RunAtLoad` and `KeepAlive`.

### Service settings

Moy supports the following LaunchAgent settings.

| Setting | Purpose |
| --- | --- |
| `Label` | Generated as `com.sputnik-apps.moy.<Identifier>`. Identifier is immutable after creation. |
| `ProgramArguments` | Absolute executable path followed by ordered arguments. |
| `WorkingDirectory` | Optional working directory. |
| `EnvironmentVariables` | Environment variables passed to the process. |
| `RunAtLoad` | Start when the LaunchAgent is loaded. Off by default. |
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
