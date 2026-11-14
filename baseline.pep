# The baseline `--baseline` reads and `--write-baseline` writes: the
# functions allowed over `--max`, each with the cognitive score it may not
# go over. One function per line, `path name score`, sorted by path and
# then name; `#` starts a comment line. A function is keyed by its file and
# name, not its line, which shifts as the file changes.

import [File, Path] from io;

# A baseline as read: the allowed score of each key, and the keys in the
# order the file lists them.
struct _Baseline {
    var allowed: HashMap<String, int> = HashMap<String, int>();
    var keys: String[] = Array<String>();

    construct() {}
}

# The key of the function `name` in `file`.
_key(file: String, name: String): String {
    return file + " " + name;
}

# Reads the baseline at `path` into `into`; returns what is wrong with it,
# clang-style, or an empty string.
_read_baseline(path: Path, into: _Baseline): String {
    var name = path.to_string();
    var text = File.read_to_string(path);
    if (text.is_err()) {
        return $"pep-complexity: error: cannot read '{name}': {text.error().message}";
    }
    var number = 0;
    for (var line in text.value().lines()) {
        number += 1;
        var entry = line.trim();
        if (entry.is_empty or entry.starts_with("#")) {
            continue;
        }
        # The name has no spaces and the score none, so the path may.
        var last = entry.rfind(" ");
        if (last <= 0 or !entry.substr_bytes(0, last as ulong).contains(" ")) {
            return $"{name}:{number}:1: error: expected 'path name score'";
        }
        var key = entry.substr_bytes(0, last as ulong);
        var score = int.parse(entry.substr_bytes(last as ulong + 1, entry.size - last as ulong - 1));
        if (!score.is_value() or score.value() < 0) {
            return $"{name}:{number}:{last + 2}: error: expected a score of 0 or more";
        }
        if (into.allowed.contains(key)) {
            return $"{name}:{number}:1: error: '{key}' is listed twice";
        }
        into.allowed[key] = score.value();
        into.keys.append(key);
    }
    return "";
}

# Writes the baseline at `path`: each key in `scores`, the highest score of
# its functions (overloads share a key), sorted. Returns what went wrong,
# or an empty string.
_write_baseline(path: Path, scores: HashMap<String, int>, keys: String[], limit: int): String {
    keys.sort((a, b) => a.compare(b));
    var text = $"# The functions allowed over pep-complexity --max {limit}, each with the\n"
        + "# cognitive score it may not go over: `path name score`. Written by\n"
        + "# --write-baseline; lower or remove a line as its function improves.\n";
    for (var key in keys) {
        text += $"{key} {scores[key]}\n";
    }
    var written = File.write_text(path, text);
    if (written.is_err()) {
        return $"pep-complexity: error: cannot write '{path.to_string()}': {written.error().message}";
    }
    return "";
}
