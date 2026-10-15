import ArgumentParser

@main
struct MoyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "moy",
        abstract: "Manage LaunchAgents and root LaunchDaemons created by Moy.",
        version: "0.2.0",
        subcommands: [
            InternalDaemonCommand.self,
            InternalRotateLogsCommand.self,
            InternalRepositoryCommand.self,
            AddCommand.self,
            ImportCommand.self,
            ExportCommand.self,
            EditCommand.self,
            RemoveCommand.self,
            ListCommand.self,
            ShowCommand.self,
            EnableCommand.self,
            DisableCommand.self,
            RestartCommand.self,
            StatusCommand.self,
            LogsCommand.self,
        ],
    )
}
