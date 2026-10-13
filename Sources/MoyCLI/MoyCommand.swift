import ArgumentParser

@main
struct MoyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "moy",
        abstract: "Manage user LaunchAgents created by Moy.",
        version: "0.1.0",
        subcommands: [
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
