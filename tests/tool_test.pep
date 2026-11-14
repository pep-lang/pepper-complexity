# Runs the built pep-complexity, found on the PATH (tests/run.sh puts it
# there), on tests/testdata/ from the package's root.

import json;
import process;

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
