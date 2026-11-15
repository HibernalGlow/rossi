//! Regression tests for the quickjs-ng `await using` use-after-free.
//!
//! `for (await using x of ...)` must be rejected outside async functions
//! (class static blocks in scripts, plain functions in modules). The parser
//! previously accepted it and emitted `OP_await` into a normal frame, which
//! left captured variables pointing into a dead C stack frame.

use rquickjs::{Context, Runtime};

fn eval_error_message(src: &str) -> String {
    let rt = Runtime::new().expect("runtime");
    let ctx = Context::full(&rt).expect("context");
    ctx.with(|ctx| {
        let err = ctx.eval::<(), _>(src).expect_err("script must fail");
        let caught = ctx.catch();
        if let Some(obj) = caught.as_object() {
            if let Ok(msg) = obj.get::<_, String>("message") {
                return msg;
            }
        }
        format!("{err}")
    })
}

fn eval_ok(src: &str) {
    let rt = Runtime::new().expect("runtime");
    let ctx = Context::full(&rt).expect("context");
    ctx.with(|ctx| ctx.eval::<(), _>(src).expect("script must compile"));
}

#[test]
fn await_using_in_class_static_block_is_rejected() {
    let msg = eval_error_message(
        r#"
        class D { [Symbol.dispose]() {} }
        const d = new D();
        let leak;
        class C { static {
          for (await using x of [d, d]) leak = () => x;
        }}
        "#,
    );
    assert!(msg.contains("await using"), "unexpected error: {msg}");
}

#[test]
fn await_using_in_plain_function_is_rejected() {
    // In a script, `await` is an identifier inside a plain function, so the
    // pre-existing parser path rejects this before the await-using guard.
    // Either way it must not compile.
    let msg = eval_error_message(
        r#"
        function f() {
          for (await using x of []) {}
        }
        "#,
    );
    assert!(!msg.is_empty(), "script must fail to compile");
}

#[test]
fn await_using_in_async_function_still_compiles() {
    eval_ok(
        r#"
        async function f() {
          for (await using x of []) {}
        }
        "#,
    );
}

#[test]
fn for_await_using_prefix_still_compiles() {
    eval_ok(
        r#"
        async function f() {
          for await (using x of []) {}
        }
        "#,
    );
}
