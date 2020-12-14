// Copyright (c) 2020 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
import os
import flag

const (
	tool_name        = os.file_name(os.executable())
	tool_version     = '0.0.2'
	tool_description = 'Prints all V functions in .v files under PATH/, that do not yet have documentation comments.'
)

enum Mode {
	missing_fn_doc
	c_in_v
}

struct UndocumentedFN {
	line      int
	signature string
	tags      []string
}

// CFN represents C.*() aka. C functions (called in V code).
struct CFN {
	line      int
	signature string
}

struct Options {
	show_help    bool
	collect_tags bool
	deprecated   bool
	mode         Mode
}

// collect traverses `path` recursively and collect files in `l` letting the user provide
// the collecting logic via function argument `f`.
fn collect(path string, mut l []string, f fn (string, mut []string)) {
	if !os.is_dir(path) {
		return
	}
	mut files := os.ls(path) or { return }
	for file in files {
		p := path + os.path_separator + file
		if os.is_dir(p) && !os.is_link(p) {
			collect(p, mut l, f)
		} else if os.exists(p) {
			f(p, mut l)
		}
	}
	return
}

// report_undocumented_functions_in_path reports to stdout all function signatures that does not
// have any comments attached.
fn report_undocumented_functions_in_path(opt Options, path string) {
	mut files := []string{}
	collect_fn := fn (path string, mut l []string) {
		if os.file_ext(path) == '.v' {
			l << os.real_path(path)
		}
	}
	collect(path, mut files, collect_fn)
	for f in files {
		contents := os.read_file(f) or { panic(err) }
		lines := contents.split('\n')
		// Skip test files
		if f.ends_with('_test.v') {
			continue
		}
		mut info := []UndocumentedFN{}
		for i, line in lines {
			if line.starts_with('pub fn') ||
				(line.starts_with('fn ') && !(line.starts_with('fn C.') || line.starts_with('fn main'))) {
				// println('Match: $line')
				if i > 0 && lines.len > 0 {
					mut line_above := lines[i - 1]
					if !line_above.starts_with('//') {
						mut tags := []string{}
						mut grab := true
						for j := i - 1; j >= 0; j-- {
							prev_line := lines[j]
							if prev_line.contains('}') { // We've looked back to the above scope, stop here
								break
							} else if prev_line.starts_with('[') {
								tags << collect_tags(prev_line)
								continue
							} else if prev_line.starts_with('//') { // Single-line comment
								grab = false
								break
							}
						}
						if grab {
							clean_line := line.all_before_last(' {')
							info << UndocumentedFN{i + 1, clean_line, tags}
						}
					}
				}
			}
		}
		if info.len > 0 {
			for undocumented_fn in info {
				tags_str := if opt.collect_tags && undocumented_fn.tags.len > 0 { '$undocumented_fn.tags' } else { '' }
				if opt.deprecated {
					println('$f:$undocumented_fn.line:0:$undocumented_fn.signature $tags_str')
				} else {
					if 'deprecated' !in undocumented_fn.tags {
						println('$f:$undocumented_fn.line:0:$undocumented_fn.signature $tags_str')
					}
				}
			}
		}
	}
}

// report_c_functions_in_pure_v_code reports to stdout all lines with C.*() function signatures
// found in any *.v files.
fn report_c_functions_in_pure_v_code(opt Options, path string) {
	mut files := []string{}
	collect_fn := fn (path string, mut l []string) {
		if path.ends_with('.c.v') {
			return
		} else if os.file_ext(path) == '.v' {
			l << os.real_path(path)
		}
	}
	collect(path, mut files, collect_fn)
	for f in files {
		contents := os.read_file(f) or { panic(err) }
		lines := contents.split('\n')

		mut results := []CFN{}
		for i, line in lines {
			if line.contains(' C.') {
				if line.starts_with('//') {
					continue
				}
				clean_line := line
				results << CFN{i + 1, clean_line}
				// println('Match: $line')
			}
		}
		if results.len > 0 {
			for c_fn in results {
				println('$f:$c_fn.line:0:$c_fn.signature')
			}
		}
	}
}

// collect_tags returns a string list of all V tags found in `line`.
fn collect_tags(line string) []string {
	mut cleaned := line.all_before('/')
	cleaned = cleaned.replace_each(['[', '', ']', '', ' ', ''])
	return cleaned.split(',')
}

fn main() {
	if os.args.len == 1 {
		println('Usage: $tool_name PATH \n$tool_description\n$tool_name -h for more help...')
		exit(1)
	}
	mut fp := flag.new_flag_parser(os.args[1..])
	fp.application(tool_name)
	fp.version(tool_version)
	fp.description(tool_description)
	fp.arguments_description('PATH [PATH]...')
	// Collect tool options
	opt := Options{
		show_help: fp.bool('help', `h`, false, 'Show this help text.')
		deprecated: fp.bool('deprecated', `d`, false, 'Include deprecated functions in output.')
		collect_tags: fp.bool('tags', `t`, false, 'Also print function tags if any is found.')
		mode: if fp.string('mode', `m`, 'missing_doc', 'Also print function tags if any is found.') == 'missing_doc' { Mode.missing_fn_doc } else { Mode.c_in_v }
	}

	if opt.show_help {
		println(fp.usage())
		exit(0)
	}

	match opt.mode {
		.missing_fn_doc {
			for path in os.args[1..] {
				report_undocumented_functions_in_path(opt, path)
			}
		}
		.c_in_v {
			for path in os.args[1..] {
				report_c_functions_in_pure_v_code(opt, path)
			}
		}
	}
}
