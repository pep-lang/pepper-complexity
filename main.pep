# pep-complexity: the cognitive and cyclomatic complexity of each Pepper
# function, like complexipy and gocognit.
#
#     pep-complexity runtime/ tools/          # every function, most complex first
#     pep-complexity --max 15 src/            # exit 1 when any is over 15, listing those
#     pep-complexity --top 10 --json src/     # the ten most complex, as JSON
#
# The README documents every option, the output and the scoring rules.

import cli;
import [File, glob, Path] from io;
import [JsonValue] from json;
import compiler.parse;
import process;
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
        "pep-complexity", "Scores the cognitive and cyclomatic complexity of Pepper functions.", version = "0.1.0"
    );
    var max = parser.option<int>(
        "max", help = "list only functions whose cognitive score is over N, and exit with 1 if any is", value_name = "N"
    );
    var top = parser.option<int>("top", help = "list only the first N functions", value_name = "N");
    var as_json = parser.flag("json", help = "write a JSON array instead of lines");
    var sources = parser.positionals("paths", "files, and directories to search for .pep files", required = true);
    if (!parser.parse(args)) {
        return 2;
    }
    var found = Array<_Found>();
    var failed = false;
    for (var source in sources.values()) {
        for (var file in _files(Path(source))) {
            if (!_score_file(file, found)) {
                failed = true;
            }
        }
    }
    # Stable: equal scores keep file and line order.
    found.sort(
        (a, b) => a.score.cognitive != b.score.cognitive ?
            b.score.cognitive - a.score.cognitive :
            b.score.cyclomatic - a.score.cyclomatic
    );
    var limit = max.value_or(-1);
    var count = top.value_or(-1);
    var listed = Array<_Found>();
    for (var each in found) {
        if (each.score.cognitive > limit and (count < 0 or listed.count < count as ulong)) {
            listed.append(each);
        }
    }
    if (as_json.is_set) {
        _print_json(listed);
    } else {
        for (var each in listed) {
            print($"{each.file}:{each.score.line} {each.score.name} {each.score.cognitive} {each.score.cyclomatic}");
        }
    }
    return failed or (limit >= 0 and !listed.is_empty) ? 1 : 0;
}

# A file as given, or every `.pep` file under a directory, skipping
# directories whose names start with `.` (`.git`, a project's `.pep`).
_files(path: Path): Path[] {
    if (!path.is_directory()) {
        return [path];
    }
    var root = path.to_string();
    var out = Array<Path>();
    for (var file in glob(root + "/**/*.pep")) {
        var below = file.to_string().substr_bytes(root.size, file.to_string().size - root.size).replace("\\", "/");
        if (!below.contains("/.")) {
            out.append(file);
        }
    }
    return out;
}

# Scores `file` into `found`; false after reporting why it could not.
_score_file(file: Path, found: _Found[]): bool {
    # One separator on every system, so output compares across them.
    var name = file.to_string().replace("\\", "/");
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
