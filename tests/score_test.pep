# The scores of small functions, each worked out by hand from the rules of
# SonarSource's "Cognitive Complexity" white paper (cognitive) and McCabe's
# count of decisions plus one (cyclomatic). The README's table states each
# rule. The white paper's own examples, translated to Pepper, come first.

import complexity;

# The score of the function `name` in `source`.
score_of(source: String, name: String): complexity.FunctionScore {
    var scores = complexity.score_source(source);
    assert(scores.is_ok(), "the source parses");
    for (var score in scores.value()) {
        if (score.name == name) {
            return score;
        }
    }
    panic($"no function '{name}'");
    return complexity.FunctionScore("", 0);
}

# Expects the function `name` in `source` to score `cognitive` and `cyclomatic`.
expect_scores(source: String, name: String, cognitive: int, cyclomatic: int) {
    var score = score_of(source, name);
    expect_equal(score.cognitive, cognitive);
    expect_equal(score.cyclomatic, cyclomatic);
}

# The white paper's `sumOfPrimes`: for +1, nested for +2, if +3, `continue
# OUT` +1.
[Test]
white_paper_sum_of_primes() {
    var source = "sum_of_primes(max: int): int {\n"
        + "    var total = 0;\n"
        + "    outer: for (var i in 1..max + 1) {\n"
        + "        for (var j in 2..i) {\n"
        + "            if (i % j == 0) {\n"
        + "                continue outer;\n"
        + "            }\n"
        + "        }\n"
        + "        total += i;\n"
        + "    }\n"
        + "    return total;\n"
        + "}\n";
    expect_scores(source, "sum_of_primes", 7, 4);
}

# The white paper's `getWords`: one switch, +1 however many cases.
[Test]
white_paper_get_words() {
    var source = "get_words(number: int): String {\n"
        + "    match (number) {\n"
        + "        1 => { return \"one\"; }\n"
        + "        2 => { return \"a couple\"; }\n"
        + "        3 => { return \"a few\"; }\n"
        + "        else => { return \"lots\"; }\n"
        + "    }\n"
        + "}\n";
    expect_scores(source, "get_words", 1, 4);
}

# The white paper's `overriddenSymbolFrom`, total 19: if +1, for +1, if +2,
# && +1, if +3, if +4, if +5, else if +1, if +1.
[Test]
white_paper_overridden_symbol_from() {
    var source = "overridden_symbol_from(class_type: ClassType): Symbol {\n"
        + "    if (class_type.is_unknown()) {\n"
        + "        return unknown_symbol;\n"
        + "    }\n"
        + "    var unknown_found = false;\n"
        + "    for (var symbol in class_type.members(name)) {\n"
        + "        if (symbol.is_method() && !symbol.is_static()) {\n"
        + "            if (can_override(symbol)) {\n"
        + "                var overriding = check_overriding(symbol, class_type);\n"
        + "                if (overriding == __null) {\n"
        + "                    if (!unknown_found) {\n"
        + "                        unknown_found = true;\n"
        + "                    }\n"
        + "                } else if (overriding.value) {\n"
        + "                    return symbol;\n"
        + "                }\n"
        + "            }\n"
        + "        }\n"
        + "    }\n"
        + "    if (unknown_found) {\n"
        + "        return unknown_symbol;\n"
        + "    }\n"
        + "    return __null;\n"
        + "}\n";
    expect_scores(source, "overridden_symbol_from", 19, 10);
}

# The white paper's mixed operators: if +1, then `&&`, `||`, `&&` are three
# runs, +3.
[Test]
white_paper_operator_runs() {
    var source = "f(a: bool, b: bool, c: bool, d: bool, e: bool, g: bool): int {\n"
        + "    if (a && b && c || d || e && g) {\n"
        + "        return 1;\n"
        + "    }\n"
        + "    return 0;\n"
        + "}\n";
    expect_scores(source, "f", 4, 7);
}

# The white paper's lambda: no increment, but the `if` inside is nested once.
[Test]
white_paper_lambda_nests() {
    var source = "f(condition: bool) {\n"
        + "    var run = () => {\n"
        + "        if (condition) {\n"
        + "            print(\"yes\");\n"
        + "        }\n"
        + "    };\n"
        + "    run();\n"
        + "}\n";
    expect_scores(source, "f", 2, 2);
}

[Test]
straight_line_code_scores_nothing() {
    expect_scores("f(x: int): int {\n    var y = x + 1;\n    return y * 2;\n}\n", "f", 0, 1);
}

[Test]
if_and_else() {
    expect_scores("f(x: int): int {\n    if (x > 0) {\n        return 1;\n    }\n    return 0;\n}\n", "f", 1, 2);
    expect_scores(
        "f(x: int): int {\n    if (x > 0) {\n        return 1;\n    } else {\n        return 0;\n    }\n}\n", "f", 2, 2
    );
}

# `else if` is +1 with no nesting, the last `else` +1.
[Test]
else_if_chain() {
    var source = "f(x: int): int {\n"
        + "    if (x > 0) {\n"
        + "        return 1;\n"
        + "    } else if (x < 0) {\n"
        + "        return -1;\n"
        + "    } else {\n"
        + "        return 0;\n"
        + "    }\n"
        + "}\n";
    expect_scores(source, "f", 3, 3);
}

# An `if` written inside an `else` block is nested: if +1, else +1, if +2.
[Test]
if_inside_else_block_nests() {
    var source = "f(x: int): int {\n"
        + "    if (x > 0) {\n"
        + "        return 1;\n"
        + "    } else {\n"
        + "        if (x < 0) {\n"
        + "            return -1;\n"
        + "        }\n"
        + "    }\n"
        + "    return 0;\n"
        + "}\n";
    expect_scores(source, "f", 4, 3);
}

# `?:` counts as an `if`, and nests what is inside it.
[Test]
ternary() {
    expect_scores("f(x: int): int {\n    return x > 0 ? 1 : 0;\n}\n", "f", 1, 2);
    # if +1; the ?: nested once +2; the inner ?: nested twice +3.
    var source = "f(x: int): int {\n"
        + "    if (x > 10) {\n"
        + "        return x > 0 ? (x > 5 ? 2 : 1) : 0;\n"
        + "    }\n"
        + "    return 0;\n"
        + "}\n";
    expect_scores(source, "f", 6, 4);
}

[Test]
while_loop() {
    expect_scores("f(x: int): int {\n    while (x > 0) {\n        x -= 1;\n    }\n    return x;\n}\n", "f", 1, 2);
}

# for +1; the `while` inside +2; the `if` inside both +3.
[Test]
for_loop_nesting() {
    var source = "f(items: int[]): int {\n"
        + "    var total = 0;\n"
        + "    for (var item in items) {\n"
        + "        while (item > 0) {\n"
        + "            if (item % 2 == 0) {\n"
        + "                total += 1;\n"
        + "            }\n"
        + "            item -= 1;\n"
        + "        }\n"
        + "    }\n"
        + "    return total;\n"
        + "}\n";
    expect_scores(source, "f", 6, 4);
}

# A plain `break` or `continue` is free; one naming a label is +1.
[Test]
break_and_continue() {
    var plain = "f(x: int) {\n    while (x > 0) {\n        if (x == 3) {\n            break;\n        }\n        x -= 1;\n    }\n}\n";
    expect_scores(plain, "f", 3, 3);
    var labeled = "f(x: int) {\n"
        + "    outer: while (x > 0) {\n"
        + "        while (true) {\n"
        + "            break outer;\n"
        + "        }\n"
        + "    }\n"
        + "}\n";
    expect_scores(labeled, "f", 4, 3);
}

# A `match` statement is +1 for the whole; its arms nest. Cyclomatic counts
# each arm but `else`.
[Test]
match_statement() {
    var source = "f(shape: Shape): int {\n"
        + "    match (shape) {\n"
        + "        Circle(r) => {\n"
        + "            if (r > 0) {\n"
        + "                return r;\n"
        + "            }\n"
        + "        }\n"
        + "        Point => { return 0; }\n"
        + "        else => { return 1; }\n"
        + "    }\n"
        + "    return 2;\n"
        + "}\n";
    expect_scores(source, "f", 3, 4);
}

[Test]
match_expression() {
    var source = "f(word: String): int {\n"
        + "    return match (word) {\n"
        + "        \"import\" => 1,\n"
        + "        \"export\", \"extern\" => 2,\n"
        + "        else => 0,\n"
        + "    };\n"
        + "}\n";
    expect_scores(source, "f", 1, 3);
    # The ?: in an arm is nested once: match +1, ?: +2.
    var nested = "f(word: String, x: int): int {\n"
        + "    return match (word) {\n"
        + "        \"a\" => x > 0 ? 1 : 2,\n"
        + "        else => 0,\n"
        + "    };\n"
        + "}\n";
    expect_scores(nested, "f", 3, 3);
}

# `&&` and `||`, or `and` and `or`: +1 for each run of one operator;
# parentheses do not end a run. Cyclomatic counts every operator.
[Test]
logical_operator_runs() {
    expect_scores("f(a: bool, b: bool): bool {\n    return a && b;\n}\n", "f", 1, 2);
    expect_scores("f(a: bool, b: bool, c: bool): bool {\n    return a && b && c;\n}\n", "f", 1, 3);
    expect_scores("f(a: bool, b: bool, c: bool): bool {\n    return a && b || c;\n}\n", "f", 2, 3);
    expect_scores("f(a: bool, b: bool, c: bool): bool {\n    return a and b or c;\n}\n", "f", 2, 3);
    expect_scores("f(a: bool, b: bool, c: bool): bool {\n    return a && (b && c);\n}\n", "f", 1, 3);
    # `!` starts a new expression: the run inside it is its own.
    expect_scores("f(a: bool, b: bool, c: bool): bool {\n    return a && !(b && c);\n}\n", "f", 2, 3);
}

# `?` returns early: a path for cyclomatic, nothing for cognitive.
[Test]
error_propagation() {
    var source = "f(text: String): Result<int> {\n"
        + "    var n = parse(text)?;\n"
        + "    return Result<int>.ok(n + 1);\n"
        + "}\n";
    expect_scores(source, "f", 0, 2);
}

# A call to the function itself is +1 each, as gocognit counts it.
[Test]
recursion() {
    var source = "factorial(n: int): int {\n"
        + "    if (n <= 1) {\n"
        + "        return 1;\n"
        + "    }\n"
        + "    return n * factorial(n - 1);\n"
        + "}\n";
    expect_scores(source, "factorial", 2, 2);
    var method = "struct Node {\n"
        + "    var next: Node;\n"
        + "\n"
        + "    length(): int {\n"
        + "        return next === __null ? 1 : 1 + next.length() + this.length();\n"
        + "    }\n"
        + "}\n";
    # ?: +1; `this.length()` +1; `next.length()` is another object's.
    expect_scores(method, "Node.length", 2, 2);
}

# `with` alone only scopes; with an `else` it chooses, as `if ... else`.
[Test]
with_statement() {
    expect_scores("f() {\n    with (var s = open()) {\n        use(s);\n    }\n}\n", "f", 0, 1);
    var source = "f() {\n"
        + "    with (var s = open()) {\n"
        + "        if (s.ready) {\n"
        + "            use(s);\n"
        + "        }\n"
        + "    } else {\n"
        + "        fail();\n"
        + "    }\n"
        + "}\n";
    expect_scores(source, "f", 4, 3);
}

# Closures nest without an increment, one level per closure.
[Test]
nested_closures() {
    var source = "f(items: int[]): int[] {\n"
        + "    return items.map((x) => items.filter((y) => y > 0 ? true : false).count);\n"
        + "}\n";
    expect_scores(source, "f", 3, 2);
}

# Every function with a body, named as the README says, at its name's line.
[Test]
names_every_member() {
    var source = "struct Box {\n"
        + "    var size: int;\n"
        + "    var area: int {\n"
        + "        get {\n"
        + "            return size > 0 ? size * size : 0;\n"
        + "        }\n"
        + "    }\n"
        + "\n"
        + "    construct(size: int) {\n"
        + "        this.size = size;\n"
        + "    }\n"
        + "\n"
        + "    destruct {\n"
        + "        print(\"gone\");\n"
        + "    }\n"
        + "\n"
        + "    grow() {\n"
        + "        size += 1;\n"
        + "    }\n"
        + "}\n"
        + "\n"
        + "trait Shape {\n"
        + "    sides(): int {\n"
        + "        return 0;\n"
        + "    }\n"
        + "\n"
        + "    area(): int;\n"
        + "}\n"
        + "\n"
        + "extend int {\n"
        + "    doubled(): int {\n"
        + "        return this * 2;\n"
        + "    }\n"
        + "}\n"
        + "\n"
        + "extern int puts(char* s);\n"
        + "\n"
        + "free(): int {\n"
        + "    return 1;\n"
        + "}\n";
    var scores = complexity.score_source(source).value();
    var names = Array<String>();
    for (var score in scores) {
        names.append($"{score.name}@{score.line}");
    }
    expect_equal(
        " ".join(names),
        "Box.area.get@4 Box.construct@9 Box.destruct@13 Box.grow@17 Shape.sides@23 int.doubled@31 free@38"
    );
    expect_equal(score_of(source, "Box.area.get").cognitive, 1);
}

[Test]
syntax_error_has_a_location() {
    var scores = complexity.score_source("f() {\n    return 1\n}\n");
    expect_true(scores.is_err());
    expect_true(scores.error().message.starts_with("2:"));
    expect_true(scores.error().message.contains("error: "));
}
