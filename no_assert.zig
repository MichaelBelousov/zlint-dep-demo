//! ## What This Rule Does
//! Disallows the use of `std.debug.assert`.

const std = @import("std");

const ast_utils = @import("zlint").linter.ast_utils;
const _rule = @import("zlint").linter.rule;
const _span = @import("zlint").linter.span;

const Span = _span.Span;
const LabeledSpan = _span.LabeledSpan;
const LinterContext = @import("zlint").linter.lint_context;
const Rule = _rule.Rule;
const NodeWrapper = _rule.NodeWrapper;

const Semantic = @import("zlint").Semantic;
const Ast = Semantic.Ast;
const TokenIndex = Ast.TokenIndex;

const Error = @import("zlint").linter.Error;
const eql = std.mem.eql;

pub const meta: Rule.Meta = .{
    .name = "no-assert",
    .category = .restriction,
    .default = .warning,
};

const NoAssert = @This();

/// Do not report assert calls in test blocks or files.
allow_tests: bool = true,

fn noAssertDiagnostic(ctx: *LinterContext, span: Span) Error {
    var d = ctx.diagnostic(
        "Using `std.debug.assert` is not allowed.",
        .{LabeledSpan{ .span = span }},
    );
    d.help = .static("Congrats, this test rule worked!");
    return d;
}

pub fn runOnNode(self: *const NoAssert, wrapper: NodeWrapper, ctx: *LinterContext) void {
    const ast = ctx.ast();

    // `assert` takes a single argument, so this must handle `.call_one` as
    // well as the multi-argument call tags.
    var call_buf: [1]Ast.Node.Index = undefined;
    const call = ast.fullCall(&call_buf, wrapper.idx) orelse return;

    if (self.allow_tests) {
        if (ast_utils.isInTest(ctx, wrapper.idx)) {
            return;
        }
        if (ctx.source.pathname) |pathname| {
            if (std.mem.endsWith(u8, pathname, "test.zig")) {
                return; // skip test files
            }
        }
    }

    const callee = call.ast.fn_expr;
    // SAFETY: assigned by every branch that doesn't return early.
    var assert_span: Span = undefined;

    switch (ast.nodeTag(callee)) {
        // look for `assert(msg, args);`
        .identifier => {
            const ident_tok: TokenIndex = ast.nodeMainToken(callee);
            std.debug.assert(ast.tokens.items(.tag)[ident_tok] == .identifier);
            const ident_span = ctx.semantic.tokenSpan(ident_tok);

            if (!eql(u8, "assert", ident_span.snippet(ctx.source.text()))) {
                return;
            }

            check_local_assert: {
                const decl = ctx.semantic.resolveBinding(
                    ctx.links().getScope(callee) orelse break :check_local_assert,
                    "assert",
                    .{ .exclude = .{ .s_variable = true } },
                );
                if (decl != null) return;
            }

            assert_span = ident_span;
        },
        // look for `std.debug.assert(msg, args);`
        .field_access => {
            // .field_access data is .node_and_token: [0]=object, [1]=field_token
            const fa_data = ast.nodeData(callee).node_and_token;

            const ident_tok: TokenIndex = fa_data[1];
            std.debug.assert(ast.tokens.items(.tag)[ident_tok] == .identifier);
            const field_span = ctx.semantic.tokenSpan(ident_tok);
            if (!eql(u8, "assert", field_span.snippet(ctx.source.text()))) {
                return;
            }

            const maybe_debug: []const u8 = ast_utils.getRightmostIdentifier(ctx, fa_data[0]) orelse {
                return;
            };
            if (!eql(u8, "debug", maybe_debug)) {
                return;
            }

            assert_span = field_span;
        },
        else => return,
    }

    ctx.report(noAssertDiagnostic(ctx, assert_span));
}

pub fn rule(self: *NoAssert) Rule {
    return Rule.init(self);
}

const RuleTester = @import("zlint").linter.tester;
test NoAssert {
    const t = std.testing;

    var no_assert = NoAssert{};
    var runner = RuleTester.init(t.allocator, no_assert.rule());
    defer runner.deinit();

    const pass = &[_][:0]const u8{
        \\fn foo(Writer: type, w: *Writer) !void {
        \\  w.assert("writers are allowed", .{});
        \\}
        ,
        \\fn add(a: u32, b: u32) u32 {
        \\  return a + b;
        \\}
        \\test add {
        \\  const std = @import("std");
        \\  std.debug.assert("testing add({d}, {d})\n", .{1, 2});
        \\  try std.testing.expectEqual(3, add(1, 2));
        \\}
        ,
        \\fn assert(comptime msg: []const u8, args: anytype) void {
        \\  // some custom assert function
        \\  _ = msg;
        \\  _ = args;
        \\}
        \\fn main() void {
        \\  assert("This is a custom assert function", .{});
        \\}
        ,
        \\const assert = @import("custom_assert.zig").assert;
        \\fn main() void {
        \\  assert("this has a different signature so it wont get reported");
        \\}
        ,
        \\const custom_assert = @import("custom_assert.zig").custom_assert;
        \\fn main() void {
        \\  custom_assert("std.debug has no custom_assert function so it should not get reported", .{});
        \\}
        ,
    };

    const fail = &[_][:0]const u8{
        \\const std = @import("std");
        \\fn foo() void {
        \\  std.debug.assert("This should not be here: {d}\n", .{42});
        \\}
        ,
        \\const std = @import("std");
        \\const debug = std.debug;
        \\fn foo() void {
        \\  debug.assert("This should not be here: {d}\n", .{42});
        \\}
        ,
        \\const std = @import("std");
        \\const assert = std.debug.assert;
        \\fn foo() void {
        \\  assert("This should not be here: {d}\n", .{42});
        \\}
        ,
    };

    try runner
        .withPass(pass)
        .withFail(fail)
        .run();
}
