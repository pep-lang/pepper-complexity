# Runs the built pep-complexity, found on the PATH (tests/run.sh puts it
# there), on tests/testdata/ from the package's root.

import [File] from io;
import json;
import process;
import [TempFolder] from testing;

# Runs pep-complexity with `arguments`, reading Windows' `"\r\n"` as `"\n"`.
run_tool(arguments: String[]): process.Output {
    var tool = process.find_companion("pep-complexity");
    assert(tool.is_value(), "pep-complexity is beside the tests or on the PATH");
    var ran = process.Command(tool.value().to_string()).arguments(arguments).run();
    assert(ran.is_ok(), "pep-complexity runs");
    var output = ran.value();
    return process.Output(output.status, output.stdout.replace("\r\n", "\n"), output.stderr.replace("\r\n", "\n"));
}

[Test]
lists_every_function_most_complex_first() {
    var output = run_tool(["tests/testdata"]);
    expect_equal(output.status.code().value(), 0);
    expect_equal(
        output.stdout,
        "tests/testdata/nested/deep.pep:1 deep 4 4\n"
            + "tests/testdata/simple.pep:5 choose 1 2\n"
            + "tests/testdata/simple.pep:1 straight 0 1\n"
    );
}

[Test]
max_lists_only_functions_over_it_and_fails() {
    var over = run_tool(["--max", "1", "tests/testdata"]);
    expect_equal(over.status.code().value(), 1);
    expect_equal(over.stdout, "tests/testdata/nested/deep.pep:1 deep 4 4\n");
    var under = run_tool(["--max", "4", "tests/testdata"]);
    expect_equal(under.status.code().value(), 0);
    expect_equal(under.stdout, "");
}

[Test]
top_and_a_single_file() {
    var output = run_tool(["--top", "1", "tests/testdata/simple.pep"]);
    expect_equal(output.status.code().value(), 0);
    expect_equal(output.stdout, "tests/testdata/simple.pep:5 choose 1 2\n");
}

[Test]
json_output() {
    var output = run_tool(["--json", "--top", "1", "tests/testdata"]);
    expect_equal(output.status.code().value(), 0);
    var parsed = json.parse(output.stdout);
    assert(parsed.is_ok(), "the output is JSON");
    var first = parsed.value()[0];
    expect_equal(first["file"].as_string().value(), "tests/testdata/nested/deep.pep");
    expect_equal(first["line"].as_int().value(), 1);
    expect_equal(first["name"].as_string().value(), "deep");
    expect_equal(first["cognitive"].as_int().value(), 4);
    expect_equal(first["cyclomatic"].as_int().value(), 4);
    expect_equal(parsed.value().as_array().value().count, 1);
}

[Test]
syntax_error_is_reported_and_fails() {
    var output = run_tool(["tests/broken/broken.pep"]);
    expect_equal(output.status.code().value(), 1);
    expect_true(output.stderr.starts_with("tests/broken/broken.pep:2:"));
    expect_true(output.stderr.contains(": error: "));
}

[Test]
missing_path_is_a_usage_error() {
    expect_equal(run_tool(Array<String>()).status.code().value(), 2);
}

# A trailing separator changes nothing, and a folder starting with `.`
# directly under the argument is still skipped.
[Test]
trailing_separator_reads_the_same() {
    var plain = run_tool(["tests/testdata"]);
    var slashed = run_tool(["tests/testdata/"]);
    expect_equal(slashed.status.code().value(), 0);
    expect_equal(slashed.stdout, plain.stdout);
    expect_false(run_tool(["tests/testdata/nested/.."]).stdout.contains("hidden"));
}

# `--top` limits what is listed, not whether `--max` fails.
[Test]
max_fails_even_when_top_lists_fewer() {
    var output = run_tool(["--max", "0", "--top", "1", "tests/testdata"]);
    expect_equal(output.status.code().value(), 1);
    expect_equal(output.stdout, "tests/testdata/nested/deep.pep:1 deep 4 4\n");
}

[Test]
out_of_range_counts_are_usage_errors() {
    expect_equal(run_tool(["--top", "0", "tests/testdata"]).status.code().value(), 2);
    expect_equal(run_tool(["--top", "-1", "tests/testdata"]).status.code().value(), 2);
    expect_equal(run_tool(["--max", "-1", "tests/testdata"]).status.code().value(), 2);
    expect_equal(run_tool(["--max", "0", "tests/testdata"]).status.code().value(), 1);
}

[Test]
exclude_skips_matching_files() {
    var output = run_tool(["--exclude", "**/nested/**", "tests/testdata"]);
    expect_equal(output.status.code().value(), 0);
    expect_equal(
        output.stdout, "tests/testdata/simple.pep:5 choose 1 2\n" + "tests/testdata/simple.pep:1 straight 0 1\n"
    );
    # A file named on the command line is matched too, and globs repeat.
    var none = run_tool(["--exclude", "x", "--exclude", "**/broken.pep", "tests/broken/broken.pep"]);
    expect_equal(none.status.code().value(), 0);
    expect_equal(none.stdout, "");
}

[Test]
write_baseline_lists_functions_over_max_sorted() {
    var folder = TempFolder("write_baseline");
    var file = folder.path.join("baseline.txt");
    var output = run_tool(["--max", "0", "--write-baseline", file.to_string(), "tests/testdata"]);
    expect_equal(output.status.code().value(), 0);
    expect_equal(output.stdout, "");
    var written = File.read_to_string(file).value().replace("\r\n", "\n");
    expect_true(written.starts_with("# "));
    expect_true(written.ends_with("\ntests/testdata/nested/deep.pep deep 4\ntests/testdata/simple.pep choose 1\n"));
    # What it wrote passes.
    expect_equal(run_tool(["--max", "0", "--baseline", file.to_string(), "tests/testdata"]).status.code().value(), 0);
}

# Runs `--max 1 --baseline` with a baseline of `lines` on tests/testdata.
run_with_baseline(name: String, lines: String): process.Output {
    var folder = TempFolder(name);
    var file = folder.path.join("baseline.txt");
    File.write_text(file, lines);
    return run_tool(["--max", "1", "--baseline", file.to_string(), "tests/testdata"]);
}

[Test]
baseline_allows_listed_functions_up_to_their_score() {
    var output = run_with_baseline("baseline_allows", "# allowed\ntests/testdata/nested/deep.pep deep 4\n");
    expect_equal(output.status.code().value(), 0);
    expect_equal(output.stdout, "");
    expect_equal(output.stderr, "");
}

[Test]
baseline_fails_a_function_whose_score_went_up() {
    var output = run_with_baseline("baseline_up", "tests/testdata/nested/deep.pep deep 3\n");
    expect_equal(output.status.code().value(), 1);
    expect_equal(output.stdout, "tests/testdata/nested/deep.pep:1 deep 4 4\n");
}

[Test]
baseline_fails_a_function_it_does_not_list() {
    var output = run_with_baseline("baseline_new", "tests/testdata/simple.pep choose 1\n");
    expect_equal(output.status.code().value(), 1);
    expect_equal(output.stdout, "tests/testdata/nested/deep.pep:1 deep 4 4\n");
}

[Test]
baseline_notes_what_improved_or_vanished() {
    var output = run_with_baseline(
        "baseline_notes", "tests/testdata/nested/deep.pep deep 6\ntests/testdata/simple.pep choose 3\n"
    );
    expect_equal(output.status.code().value(), 0);
    expect_equal(
        output.stderr,
        "pep-complexity: note: 'tests/testdata/nested/deep.pep deep' is down to 4 from 6: lower it in the baseline\n"
            + "pep-complexity: note: 'tests/testdata/simple.pep choose' is no longer over 1: remove it from the baseline\n"
    );
}

[Test]
bad_baseline_is_an_error_at_its_line() {
    var output = run_with_baseline("baseline_bad", "# comment\n\ntests/testdata/simple.pep choose many\n");
    expect_equal(output.status.code().value(), 1);
    expect_true(output.stderr.contains("baseline.txt:3:"));
    expect_true(output.stderr.contains("error: expected a score of 0 or more"));
}

[Test]
baseline_needs_max() {
    expect_equal(run_tool(["--baseline", "x.txt", "tests/testdata"]).status.code().value(), 2);
    expect_equal(run_tool(["--write-baseline", "x.txt", "tests/testdata"]).status.code().value(), 2);
}

# Overloads share one line, holding the higher score, and a name may hold
# a space (an extension of a generic type); `./` is not part of a name.
[Test]
write_baseline_merges_overloads_and_keeps_spaced_names() {
    var folder = TempFolder("write_baseline_overloads");
    var file = folder.path.join("baseline.txt");
    var output = run_tool(["--max", "0", "--write-baseline", file.to_string(), "./tests/overloads"]);
    expect_equal(output.status.code().value(), 0);
    var written = File.read_to_string(file).value().replace("\r\n", "\n");
    expect_true(
        written.ends_with("\ntests/overloads/overloads.pep Pair<K, V>.keyed 1\ntests/overloads/overloads.pep pick 2\n")
    );
    expect_false(written.contains("./"));
    # Read back: both functions are allowed, and a note names the whole key.
    File.write_text(file, "tests/overloads/overloads.pep Pair<K, V>.keyed 3\ntests/overloads/overloads.pep pick 2\n");
    var checked = run_tool(["--max", "0", "--baseline", file.to_string(), "tests/overloads"]);
    expect_equal(checked.status.code().value(), 0);
    expect_equal(
        checked.stderr,
        "pep-complexity: note: 'tests/overloads/overloads.pep Pair<K, V>.keyed' is down to 1 from 3: lower it in the baseline\n"
    );
}

# A baseline's paths are read in the output's form: `\` is `/`, and a
# leading `./` is dropped.
[Test]
baseline_paths_are_normalised() {
    var output = run_with_baseline("baseline_normalised", "./tests\\testdata/nested/deep.pep deep 4\n");
    expect_equal(output.status.code().value(), 0);
    expect_equal(output.stdout, "");
    expect_equal(output.stderr, "");
}

# A file that does not parse would lose its functions from the baseline:
# nothing is written.
[Test]
write_baseline_refuses_after_a_parse_error() {
    var folder = TempFolder("write_baseline_broken");
    var file = folder.path.join("baseline.txt");
    var output = run_tool(["--max", "0", "--write-baseline", file.to_string(), "tests/broken", "tests/testdata"]);
    expect_equal(output.status.code().value(), 1);
    expect_false(file.exists());
}
