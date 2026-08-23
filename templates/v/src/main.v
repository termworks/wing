module main

import os

// The version lives in v.mod; this mirrors it so `--version` has something to print without
// reading a file at runtime. Keep the two in step when cutting a release.
const version = '0.1.0'

fn greeting() string {
	return 'hello from {{kebab_name}}'
}

fn main() {
	args := os.args[1..]
	if args.len > 0 && args[0] in ['-h', '--help'] {
		println('{{PROJECT_NAME}}')
		println('')
		println('Usage:')
		println('  {{kebab_name}} [--help] [--version]')
		return
	}
	if args.len > 0 && args[0] in ['-V', '--version'] {
		println(version)
		return
	}
	println(greeting())
}
