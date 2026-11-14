# pep-complexity: the cognitive and cyclomatic complexity of each Pepper
# function, like complexipy and gocognit.
#
#     pep-complexity runtime/ tools/          # every function, most complex first
#     pep-complexity --max 15 src/            # exit 1 when any is over 15, listing those
#     pep-complexity --top 10 --json src/     # the ten most complex, as JSON
#     pep-complexity --max 25 --baseline allowed.txt --exclude '**/*_test.pep' src/
#
# The README documents every option, the output and the scoring rules.

import cli;
import [File, glob, glob_matches, Path] from io;
import [JsonValue] from json;
import compiler.parse;
import process;
import "baseline";
import "score";

# A scored function and the file it is in.
struct _Found {
    var file: String;
    var score: FunctionScore;

    construct(file: String, score: FunctionScore) {
        this.file = file;
        this.score = score;
    }
}

# On the parser's big stack, which the deepest source fits in.
main(): int {
    return parse.on_compiler_stack(() => _main(process.arguments()));
}

_main(args: String[]): int {
    var parser = cli.Parser(
        "pep-complexity", "Scores the cognitive and cyclomatic complexity of Pepper functions.", version = "0.2.0"
    );
    var max = parser.option<int>(
        "max", help = "list only functions whose cognitive score is over N, and exit with 1 if any is", value_name = "N"
    );
    var top = parser.option<int>("top", help = "list only the first N functions", value_name = "N");
    var as_json = parser.flag("json", help = "write a JSON array instead of lines");
    var baseline = parser.option(
        "baseline", help = "with --max, allow the functions FILE lists, up to their scores there", value_name = "FILE"
    );
    var write_baseline = parser.option(
        "write-baseline",
        help = "with --max, write the functions over it to FILE, and list nothing",
        value_name = "FILE"
    );
    var excludes = parser.multiple(
        "exclude",
        help = "skip the files whose path matches GLOB, such as '**/*_test.pep'; repeatable",
        value_name = "GLOB"
    );
    var sources = parser.positionals("paths", "files, and directories to search for .pep files", required = true);
    if (!parser.parse(args)) {
        return 2;
    }
    if (max.is_set and max.value() < 0) {
        return parser.usage_error("'--max' needs 0 or more");
    }
    if (top.is_set and top.value() < 1) {
        return parser.usage_error("'--top' needs 1 or more");
    }
    if ((baseline.is_set or write_baseline.is_set) and !max.is_set) {
        return parser.usage_error("'--baseline' and '--write-baseline' need '--max'");
    }
    var allowed = _Baseline();
    if (baseline.is_set) {
        var error = _read_baseline(Path(baseline.value()), allowed);
        if (!error.is_empty) {
            File.stderr().write_all(error + "
");
            return 1;
        }
    }
    var found = Array<_Found>();
    var failed = !_score_paths(sources.values(), excludes.values(), found);
    var limit = max.value_or(-1);
    # The highest score over the limit of each key, for the baseline.
    var over = HashMap<String, int>();
    var over_keys = Array<String>();
    var failing = Array<_Found>();
    for (var each in found) {
        if (each.score.cognitive <= limit) {
            continue;
        }
        var key = _key(each.file, each.score.name);
        var known = over.try_get(key);
        if (!known.is_value()) {
            over_keys.append(key);
        }
        if (!known.is_value() or known.value() < each.score.cognitive) {
            over[key] = each.score.cognitive;
        }
        var allowance = allowed.allowed.try_get(key);
        if (!allowance.is_value() or each.score.cognitive > allowance.value()) {
            failing.append(each);
        }
    }
    if (write_baseline.is_set) {
        var error = _write_baseline(Path(write_baseline.value()), over, over_keys, limit);
        if (!error.is_empty) {
            File.stderr().write_all(error + "
");
            return 1;
        }
        return failed ? 1 : 0;
    }
    _note_improvements(allowed, over, limit);
    _list(failing, top.value_or(-1), as_json.is_set);
    return failed or (limit >= 0 and !failing.is_empty) ? 1 : 0;
}

# Scores every file `sources` names into `found`, most complex first,
# skipping those a glob of `excludes` matches; false after reporting a file
# it could not score.
_score_paths(sources: String[], excludes: String[], found: _Found[]): bool {
    var succeeded = true;
    for (var source in sources) {
        for (var file in _files(Path(source))) {
            if (!_excluded(file, excludes) and !_score_file(file, found)) {
                succeeded = false;
            }
        }
    }
    # Stable: equal scores keep file and line order.
    found.sort(
        (a, b) => a.score.cognitive != b.score.cognitive ?
            b.score.cognitive - a.score.cognitive :
            b.score.cyclomatic - a.score.cyclomatic
    );
    return succeeded;
}

# Whether `file`, as the output names it, matches one of `excludes`.
_excluded(file: Path, excludes: String[]): bool {
    var name = _name(file);
    for (var pattern in excludes) {
        if (glob_matches(pattern, name)) {
            return true;
        }
    }
    return false;
}

# Notes each function of the baseline that is now under its score there,
# or no longer over the limit, so the baseline can shrink.
_note_improvements(allowed: _Baseline, over: HashMap<String, int>, limit: int) {
    for (var key in allowed.keys) {
        # The name has no spaces, so the last one ends the path.
        var split = key.rfind(" ") as ulong;
        var at = $"pep-complexity: note: {key.substr_bytes(0, split)}: '{key.substr_bytes(split + 1, key.size - split - 1)}'";
        var now = over.try_get(key);
        if (!now.is_value()) {
            File.stderr().write_all($"{at} is no longer over {limit}: remove it from the baseline
");
        } else if (now.value() < allowed.allowed[key]) {
            File.stderr().write_all(
                $"{at} is down to {now.value()} from {allowed.allowed[key]}: lower it in the baseline
"
            );
        }
    }
}

# Prints the first `count` of `listed` (all when `count` is negative), as
# lines or as JSON.
_list(listed: _Found[], count: int, as_json: bool) {
    var shown = Array<_Found>();
    for (var each in listed) {
        if (count < 0 or shown.count < count as ulong) {
            shown.append(each);
        }
    }
    if (as_json) {
        _print_json(shown);
        return;
    }
    for (var each in shown) {
        print($"{each.file}:{each.score.line} {each.score.name} {each.score.cognitive} {each.score.cyclomatic}");
    }
}

# A file as given, or every `.pep` file under a directory, skipping
# directories whose names start with `.` (`.git`, a project's `.pep`).
_files(path: Path): Path[] {
    if (!path.is_directory()) {
        return [path];
    }
    var root = path.to_string();
    # `src/` is `src`, so the files under it read the same either way.
    while (root.size > 1 and (root.ends_with("/") or root.ends_with("\\"))) {
        root = root.substr_bytes(0, root.size - 1);
    }
    var out = Array<Path>();
    for (var file in glob(root + "/**/*.pep")) {
        var below = "/"
            + file.to_string().substr_bytes(root.size, file.to_string().size - root.size).replace("\\", "/");
        if (!below.contains("/.")) {
            out.append(file);
        }
    }
    return out;
}

# `file` as the output names it: one separator on every system, so output
# compares across them.
_name(file: Path): String {
    var name = file.to_string().replace("\\", "/");
    # `./src/a.pep` is `src/a.pep`, for the baseline's keys and `--exclude`.
    while (name.starts_with("./")) {
        name = name.substr_bytes(2, name.size - 2);
    }
    return name;
}

# Scores `file` into `found`; false after reporting why it could not.
_score_file(file: Path, found: _Found[]): bool {
    var name = _name(file);
    var text = File.read_to_string(file);
    if (text.is_err()) {
        File.stderr().write_all($"pep-complexity: error: cannot read '{name}': {text.error().message}\n");
        return false;
    }
    var scores = score_source(text.value());
    if (scores.is_err()) {
        File.stderr().write_all($"{name}:{scores.error().message}\n");
        return false;
    }
    for (var score in scores.value()) {
        found.append(_Found(name, score));
    }
    return true;
}

_print_json(listed: _Found[]) {
    var out = JsonValue.array();
    for (var each in listed) {
        var entry = JsonValue.object();
        entry["file"] = JsonValue.String(each.file);
        entry["line"] = JsonValue.Integer(each.score.line as long);
        entry["name"] = JsonValue.String(each.score.name);
        entry["cognitive"] = JsonValue.Integer(each.score.cognitive);
        entry["cyclomatic"] = JsonValue.Integer(each.score.cyclomatic);
        out.append(entry);
    }
    print(out.to_pretty_string());
}
