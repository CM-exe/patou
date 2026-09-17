// Embeds ../assets/favicon.ico as patou-bash.exe's icon resource, so it
// shows up as a real installed app in Explorer instead of the generic
// executable icon.
//
// Checks CARGO_CFG_TARGET_OS (the compilation *target*) rather than
// `cfg(windows)` (which build.rs itself, always compiled for the host,
// would evaluate against the *host*) so this also works when
// cross-compiling for Windows from a non-Windows machine.
//
// `patou-bash` is its own single-binary package specifically so this
// resource embedding is unambiguous: Cargo only applies an unscoped
// `cargo:rustc-link-arg`/`cargo:rustc-link-lib` (what `winresource`
// emits) to every binary in a package that has no library target, so
// sharing a build script with the unrelated `patou` binary would have
// stuck patou.exe with the same resource for no reason. See
// https://github.com/mxre/winres/issues/32 for the related pitfall with
// a package that mixes a library and binaries.
fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        let mut res = winresource::WindowsResource::new();
        res.set_icon("../assets/favicon.ico");
        // A failure here must not silently produce a broken exe: better
        // to fail the build loudly than ship a patou-bash.exe that looks
        // fine to Cargo but won't run.
        res.compile().expect("failed to embed ../assets/favicon.ico");
    }
}
