import std.stdio;

import {{snake_name}}.core;

/// The version this binary reports. dub.json holds the package version; keep the two in step.
enum versionString = "0.1.0";

void main(string[] args)
{
    if (args.length > 1 && (args[1] == "-h" || args[1] == "--help"))
    {
        writeln("{{PROJECT_NAME}}");
        writeln("");
        writeln("Usage:");
        writeln("  {{kebab_name}} [--help] [--version]");
        return;
    }
    if (args.length > 1 && (args[1] == "-V" || args[1] == "--version"))
    {
        writeln(versionString);
        return;
    }
    writeln(greeting());
}
