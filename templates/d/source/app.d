import std.stdio;

import {{snake_name}}.core;

/// The version is read from PROJECT at compile time rather than repeated here. dub.json carries no
/// version of its own, so a literal in D source is a copy nothing keeps in step: it would still say
/// 0.1.0 long after the project had moved on.
enum versionString = readProjectVersion();

private string readProjectVersion()
{
    import std.string : splitLines, startsWith, strip;

    string[] fields;
    foreach (line; import("PROJECT").splitLines())
    {
        const trimmed = line.strip();
        if (trimmed.length == 0 || trimmed.startsWith("#"))
            continue;
        fields ~= trimmed;
    }
    assert(fields.length >= 2, "PROJECT is missing its version line");
    return fields[1];
}

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
