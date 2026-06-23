import ArgumentParser

@main
struct MacFanCtl: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "macfanctl",
        abstract: "Control Mac fan speeds via SMC.",
        version: "0.3.0",
        subcommands: [
            ListCommand.self,
            WatchCommand.self,
            SetCommand.self,
            MaxCommand.self,
            AutoCommand.self,
            SetupCommand.self,
        ]
    )
}
