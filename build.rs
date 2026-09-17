// Embeds assets/favicon.ico as the icon resource on Windows binaries
// (patou.exe and patou-bash.exe) - most visibly for patou-bash.exe, which
// otherwise shows Explorer's generic executable icon and looks like it
// isn't a real installed app.
//
// Checks CARGO_CFG_TARGET_OS (the compilation *target*) rather than
// `cfg(windows)` (which build.rs itself, always compiled for the host,
// would evaluate against the *host*) so this also works when
// cross-compiling for Windows from a non-Windows machine.
fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        let mut res = winresource::WindowsResource::new();
        res.set_icon("assets/favicon.ico");
        if let Err(err) = res.compile() {
            println!("cargo:warning=failed to embed assets/favicon.ico: {err}");
        }
    }
}
