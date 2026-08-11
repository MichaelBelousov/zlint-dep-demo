//! ## What This Rule Does
//! Disallows `unreachable`.

const zlint = @import("zlint");
const Rule = zlint.linter.rule.Rule;
const NodeWrapper = zlint.linter.rule.NodeWrapper;
const LinterContext = zlint.linter.lint_context;

pub const meta: Rule.Meta = .{
    .name = "no-unreachable",
    .category = .restriction,
    .default = .warning,
};

const NoUnreachable = @This();

/// Configurable from `zlint.json`: `["warn", { "allow_tests": false }]`
allow_tests: bool = true,

pub fn runOnNode(self: *const NoUnreachable, wrapper: NodeWrapper, ctx: *LinterContext) void {
    if (wrapper.node.tag != .unreachable_literal) return;
    if (self.allow_tests and zlint.linter.ast_utils.isInTest(ctx, wrapper.idx)) return;

    ctx.report(ctx.diagnostic(
        "`unreachable` is not allowed.",
        .{ctx.spanT(wrapper.node.main_token)},
    ));
}

pub fn rule(self: *NoUnreachable) Rule {
    return Rule.init(self);
}
