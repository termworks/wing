package main

import (
	"fmt"
	"os"

	"github.com/bresilla/{{kebab_name}}/src/cmd"
)

// Filled in at link time from PROJECT: `make build` passes -X main.version. A literal here would
// be a second place to change, and the one nothing reads -- the binary is built with the flag, so
// the literal only shows up in a `go build` run by hand.
var (
	version = "dev"
	commit  = ""
	date    = ""
	builtBy = ""
)

func main() {
	cmd.Execute(buildVersion(version, commit, date, builtBy), os.Exit, os.Args[1:])
}

func buildVersion(version, commit, date, builtBy string) string {
	result := version
	if commit != "" {
		result = fmt.Sprintf("%s\ncommit: %s", result, commit)
	}
	if date != "" {
		result = fmt.Sprintf("%s\nbuilt at: %s", result, date)
	}
	if builtBy != "" {
		result = fmt.Sprintf("%s\nbuilt by: %s", result, builtBy)
	}
	return result
}
