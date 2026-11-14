## Scoring each function of a Pepper source file: its cognitive complexity,
## after SonarSource's white paper as gocognit implements it, and its
## cyclomatic (McCabe) complexity, both from one walk of the function body
## that the compiler's own parser builds.

import compiler.ast;
import [Block, Declaration, Expression, FunctionDecl, MatchExpression, Statement, StringPart] from compiler.ast;
import compiler.parse;
import syntax;

## One function's scores.
export struct FunctionScore {
    ## The function's name; a member is `Type.name`, a constructor
    ## `Type.construct`, a destructor `Type.destruct`, and a property's
    ## accessor `Type.property.get` or `.set`.
    var name: String;
    ## The line of its name, from 1.
    var line: ulong;
    ## Its cognitive complexity: 0 for straight-line code.
    var cognitive: int;
    ## Its cyclomatic complexity: 1 for straight-line code.
    var cyclomatic: int;

    ## Creates a score.
    ##
    ## @param name the function's name
    ## @param line the line of its name
    ## @param cognitive its cognitive complexity
    ## @param cyclomatic its cyclomatic complexity
    construct(name: String, line: ulong, cognitive: int = 0, cyclomatic: int = 1) {
        this.name = name;
        this.line = line;
        this.cognitive = cognitive;
        this.cyclomatic = cyclomatic;
    }
}

## Scores every function with a body in `source`, in source order: free
## functions, and the methods, constructors, destructors and property
## accessors of structs, enums, traits and extensions. A closure counts
## toward the function it is written in.
##
## Parse on a big stack (`compiler.parse.on_compiler_stack`) to take
## deeply nested source.
##
## @param source the text of one source file
## @returns the scores, or the first syntax error as `line:column: error: message`
## @example
##     var scores = complexity.score_source("f(x: int): int {\n    if (x > 0) {\n        return 1;\n    }\n    return 0;\n}\n");
##     # scores.value()[0]: name "f", line 1, cognitive 1, cyclomatic 2
export score_source(source: String): Result<FunctionScore[]> {
    var parsed = parse.parse_written(source);
    if (parsed.is_err()) {
        var error = parsed.error();
        var line = syntax.line_of(source, error.span.start);
        var column = syntax.column_of(source, error.span.start);
        return Result<FunctionScore[]>.err(Error($"{line}:{column}: error: {error.message}"));
    }
    var out = Array<FunctionScore>();
    for (var declaration in parsed.value().declarations) {
        _score_declaration(source, declaration, out);
    }
    # Members are gathered kind by kind: put them back in source order.
    out.sort((a, b) => a.line < b.line ? -1 : (a.line > b.line ? 1 : 0));
    return Result<FunctionScore[]>.ok(out);
}

_score_declaration(source: String, declaration: Declaration, out: FunctionScore[]) {
    match (declaration) {
        Function(decl) => {
            _score_function(source, "", decl, out);
        }
        Struct(decl) => {
            var prefix = decl.name + ".";
            for (var constructor in decl.constructors) {
                _score_function(source, prefix, constructor, out);
            }
            if (decl.destructor.is_value()) {
                var at = decl.destruct_span.is_value() ? decl.destruct_span.value().start : decl.span.start;
                out.append(_score_body(source, prefix + "destruct", "", at, decl.destructor.value()));
            }
            _score_members(source, prefix, decl.methods, decl.properties, out);
        }
        Trait(decl) => {
            _score_members(source, decl.name + ".", decl.methods, decl.properties, out);
        }
        Extend(decl) => {
            _score_members(source, decl.target.to_string() + ".", decl.methods, decl.properties, out);
        }
        else => {}
    }
}

_score_members(
    source: String, prefix: String, methods: FunctionDecl[], properties: ast.PropertyDecl[], out: FunctionScore[]
) {
    for (var method in methods) {
        _score_function(source, prefix, method, out);
    }
    for (var property in properties) {
        if (property.getter.is_value()) {
            _score_accessor(source, prefix + property.name + ".get", property.getter.value(), out);
        }
        if (property.setter.is_value()) {
            _score_accessor(source, prefix + property.name + ".set", property.setter.value(), out);
        }
    }
}

# `get;` and `set;` have an empty body: nothing written, nothing scored.
_score_accessor(source: String, name: String, accessor: ast.Accessor, out: FunctionScore[]) {
    var body = accessor.function.body;
    if (body.is_value() and !body.value().statements.is_empty) {
        out.append(_score_body(source, name, "", accessor.span.start, body.value()));
    }
}

_score_function(source: String, prefix: String, decl: FunctionDecl, out: FunctionScore[]) {
    if (decl.body.is_value()) {
        # A constructor cannot call itself by name, so it has no recursion to find.
        var callee = decl.name == "construct" ? "" : decl.name;
        out.append(_score_body(source, prefix + decl.name, callee, decl.name_span.start, decl.body.value()));
    }
}

_score_body(source: String, name: String, callee: String, at: ulong, body: Block): FunctionScore {
    var scorer = _Scorer(callee);
    scorer.walk_block(body);
    return FunctionScore(name, syntax.line_of(source, at), scorer.cognitive, scorer.cyclomatic);
}

_is_and(op: String): bool {
    return op == "&&" or op == "and";
}

_is_or(op: String): bool {
    return op == "||" or op == "or";
}

_is_logical(expression: Expression): bool {
    if (expression is Binary(_, op, _, _)) {
        return _is_and(op) or _is_or(op);
    }
    if (expression is Parenthesized(value, _)) {
        return _is_logical(value);
    }
    return false;
}

# Walks one function body, adding up both scores. The rules and their
# sources are in the README's table.
struct _Scorer {
    var callee: String;
    var nesting: int;
    var cognitive: int;
    var cyclomatic: int = 1;

    construct(callee: String) {
        this.callee = callee;
    }

    walk_block(body: Block) {
        for (var statement in body.statements) {
            walk_statement(statement);
        }
    }

    # A body one level deeper.
    nested(body: Block) {
        nesting += 1;
        walk_block(body);
        nesting -= 1;
    }

    # A structure that nests: +1, plus how deeply it is nested.
    structure() {
        cognitive += 1 + nesting;
        cyclomatic += 1;
    }

    walk_statement(statement: Statement) {
        match (statement) {
            Expression(expression) => {
                walk_expression(expression);
            }
            Block(body) => {
                walk_block(body);
            }
            Declaration(declaration) => {
                if (declaration is Variable(decl)) {
                    walk_optional(decl.default_value);
                }
            }
            Branch(condition, if_block, else_block, _) => {
                structure();
                branch(condition, if_block, else_block);
            }
            While(condition, body, _) => {
                structure();
                walk_expression(condition);
                nested(body);
            }
            For(_, _, iterable, body, _) => {
                structure();
                walk_expression(iterable);
                nested(body);
            }
            With(_, scope, body, else_block, _) => {
                walk_expression(scope);
                if (else_block.is_value()) {
                    # `with ... else` chooses, as `if ... else` does.
                    structure();
                    nested(body);
                    cognitive += 1;
                    nested(else_block.value());
                } else {
                    walk_block(body);
                }
            }
            Return(value, _) => {
                walk_optional(value);
            }
            LoopBreak(_, label, _, _) => {
                if (!label.is_empty) {
                    cognitive += 1;
                }
            }
            Labeled(_, _, loop, _) => {
                walk_statement(loop);
            }
            Destructure(_, value, _, _) => {
                walk_expression(value);
            }
            Match(written) => {
                structure();
                walk_expression(written.value);
                for (var arm in written.arms) {
                    walk_optional(arm.guard);
                    nested(arm.body);
                }
                # Each arm is a path, the first included in `structure`'s.
                cyclomatic += written.arms.count as int - 1;
                if (written.else_block.is_value()) {
                    nested(written.else_block.value());
                }
            }
            Static(written) => {
                walk_block(written.block);
            }
        }
    }

    # The condition and blocks of an `if` already counted; an `else if`
    # counts +1 with no nesting, and a last `else` +1.
    branch(condition: Expression, if_block: Block, else_block: Block?) {
        walk_expression(condition);
        nested(if_block);
        if (!else_block.is_value()) {
            return;
        }
        var other = else_block.value();
        # The parser wraps `else if` in a block that spans just that `if`.
        if (other.statements.count == 1) {
            if (other.statements[0] is Branch(inner, inner_block, inner_else, span)) {
                if (span.start == other.span.start and span.end == other.span.end) {
                    cognitive += 1;
                    cyclomatic += 1;
                    branch(inner, inner_block, inner_else);
                    return;
                }
            }
        }
        cognitive += 1;
        nested(other);
    }

    walk_optional(expression: Expression?) {
        if (expression.is_value()) {
            walk_expression(expression.value());
        }
    }

    walk_expressions(expressions: Expression[]) {
        for (var expression in expressions) {
            walk_expression(expression);
        }
    }

    walk_expression(expression: Expression) {
        match (expression) {
            Binary(lhs, op, rhs, _) => {
                if (_is_and(op) or _is_or(op)) {
                    logical(expression);
                } else {
                    walk_expression(lhs);
                    walk_expression(rhs);
                }
            }
            Ternary(condition, true_expr, false_expr, _) => {
                structure();
                walk_expression(condition);
                nesting += 1;
                walk_expression(true_expr);
                walk_expression(false_expr);
                nesting -= 1;
            }
            Unary(op, prefix, operand, _) => {
                if (op == "?" and !prefix) {
                    # Propagation returns early: a path, but no break in the reading.
                    cyclomatic += 1;
                }
                walk_expression(operand);
            }
            FunctionCall(function, arguments, _) => {
                if (_calls_itself(function)) {
                    cognitive += 1;
                }
                walk_expression(function);
                walk_expressions(arguments);
            }
            Closure(closure) => {
                nested(closure.body);
            }
            Match(written) => {
                value_match(written);
            }
            Cast(value, _, _, _, _) => {
                walk_expression(value);
            }
            Index(lhs, rhs, _) => {
                walk_expression(lhs);
                walk_expression(rhs);
            }
            MemberAccess(lhs, _, _, _) => {
                walk_expression(lhs);
            }
            NamedArgument(_, _, value, _) => {
                walk_expression(value);
            }
            Tuple(elements, _, _) => {
                walk_expressions(elements);
            }
            ArrayLiteral(elements, _) => {
                walk_expressions(elements);
            }
            MapLiteral(entries, _) => {
                for (var entry in entries) {
                    walk_expression(entry.key);
                    walk_expression(entry.value);
                }
            }
            Is(value, _, _, _) => {
                walk_expression(value);
            }
            Interpolated(parts, _) => {
                holes(parts);
            }
            FormatString(parts, _, _, _) => {
                holes(parts);
            }
            Parenthesized(value, _) => {
                walk_expression(value);
            }
            else => {}
        }
    }

    holes(parts: StringPart[]) {
        for (var part in parts) {
            if (part is Hole(value, _, _)) {
                walk_expression(value);
            }
        }
    }

    value_match(written: MatchExpression) {
        structure();
        walk_expression(written.value);
        nesting += 1;
        for (var arm in written.arms) {
            walk_optional(arm.guard);
            walk_expression(arm.value);
        }
        walk_optional(written.else_value);
        nesting -= 1;
        cyclomatic += written.arms.count as int - 1;
    }

    # A run of `&&`/`||` (and `and`/`or`): cognitive +1 for each run of one
    # operator, so `a && b && c` is +1 and `a && b || c` +2; cyclomatic +1
    # for each operator. Parentheses do not end a run.
    logical(root: Expression) {
        var operators = Array<bool>();
        var operands = Array<Expression>();
        flatten(root, operators, operands);
        for (var index in 0..operators.count) {
            if (index == 0 or operators[index] != operators[index - 1]) {
                cognitive += 1;
            }
        }
        cyclomatic += operators.count as int;
        walk_expressions(operands);
    }

    # The operators of a logical run in source order (true for `&&`), and
    # the operands that are not part of it.
    flatten(expression: Expression, operators: bool[], operands: Expression[]) {
        if (expression is Parenthesized(value, _)) {
            if (_is_logical(value)) {
                flatten(value, operators, operands);
                return;
            }
        }
        if (expression is Binary(lhs, op, rhs, _)) {
            if (_is_and(op) or _is_or(op)) {
                flatten(lhs, operators, operands);
                operators.append(_is_and(op));
                flatten(rhs, operators, operands);
                return;
            }
        }
        operands.append(expression);
    }

    # A call to the function being scored, by its name or as `this.name`.
    _calls_itself(function: Expression): bool {
        if (callee.is_empty) {
            return false;
        }
        if (function is SymbolRef(id, _)) {
            return id == callee;
        }
        if (function is MemberAccess(lhs, name, _, _)) {
            if (lhs is SymbolRef(id, _)) {
                return id == "this" and name == callee;
            }
        }
        return false;
    }
}
