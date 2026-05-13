import ArgumentParser

@main
struct MacFanCtl: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "macfanctl",
        abstract: "Control Mac fan speeds via SMC.",
        version: "0.1.0",
        subcommands: [
            ListCommand.self,
            SetCommand.self,
            MaxCommand.self,
            AutoCommand.self,
            SetupCommand.self,
        ]
    )
}
