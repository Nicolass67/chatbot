//! Non-interactive sideload CLI for Chatbot Fast Deploy.
//!
//! Exit codes:
//!   0 = OK
//!   2 = HUMAN_REQUIRED (2FA / interactive)
//!   1 = FAIL
//!
//! Env:
//!   APPLE_ID
//!   APPLE_APP_SPECIFIC_PASSWORD (or APPLE_PASSWORD)
//!   IOS_SIDELLOAD_2FA_CODE (optional one-shot code)
//!   IOS_SIDELLOAD_MACHINE_NAME (optional)

use idevice::usbmuxd::{UsbmuxdAddr, UsbmuxdConnection};
use isideload::{
    auth::apple_account::{TwoFactorCallbackParams, TwoFactorCallbackResponse},
    auth::builder::AppleAccountBuilder,
    dev::developer_session::DeveloperSession,
    sideload::{
        builder::MaxCertsBehavior, SideloaderBuilder, TeamSelection,
    },
    util::fs_storage::FsStorage,
};
use std::{
    env, fs,
    path::PathBuf,
    process,
    sync::atomic::{AtomicBool, Ordering},
};
use tracing::Level;
use tracing_subscriber::FmtSubscriber;

static NEED_HUMAN: AtomicBool = AtomicBool::new(false);

fn exit_human(msg: &str) -> ! {
    eprintln!("HUMAN_REQUIRED: {msg}");
    process::exit(2);
}

fn exit_fail(msg: &str) -> ! {
    eprintln!("FAIL: {msg}");
    process::exit(1);
}

fn usage() -> ! {
    eprintln!(
        "Usage: chatbot-isideload-cli install <path-to.ipa|.app>\n\
         Env: APPLE_ID + APPLE_APP_SPECIFIC_PASSWORD (or APPLE_PASSWORD)"
    );
    process::exit(1);
}

#[tokio::main]
async fn main() {
    let _ = rustls::crypto::ring::default_provider().install_default();
    if let Err(e) = isideload::init() {
        exit_fail(&format!("isideload init: {e}"));
    }
    let _ = tracing::subscriber::set_global_default(
        FmtSubscriber::builder().with_max_level(Level::INFO).finish(),
    );

    let mut args = env::args().skip(1).collect::<Vec<_>>();
    if args.is_empty() {
        usage();
    }
    let cmd = args.remove(0);
    if cmd != "install" || args.is_empty() {
        usage();
    }
    let app_path = PathBuf::from(&args[0]);
    if !app_path.exists() {
        exit_fail(&format!("path not found: {}", app_path.display()));
    }

    let apple_id = env::var("APPLE_ID").unwrap_or_default();
    let password = env::var("APPLE_APP_SPECIFIC_PASSWORD")
        .or_else(|_| env::var("APPLE_PASSWORD"))
        .unwrap_or_default();
    if apple_id.is_empty() || password.is_empty() {
        exit_human("missing APPLE_ID / APPLE_APP_SPECIFIC_PASSWORD");
    }

    let storage_dir = env::var("IOS_SIDELLOAD_STORAGE")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            let base = dirs_fallback();
            base.join("chatbot-isideload")
        });
    let _ = fs::create_dir_all(&storage_dir);

    let get_2fa = |_params: TwoFactorCallbackParams| async move {
        if let Ok(code) = env::var("IOS_SIDELLOAD_2FA_CODE") {
            let code = code.trim().to_string();
            if !code.is_empty() {
                return Ok(TwoFactorCallbackResponse::SubmitCode(code));
            }
        }
        NEED_HUMAN.store(true, Ordering::SeqCst);
        Ok(TwoFactorCallbackResponse::Abort)
    };

    let account = AppleAccountBuilder::new(&apple_id)
        .login(&password, get_2fa)
        .await;

    let mut account = match account {
        Ok(a) => a,
        Err(e) => {
            if NEED_HUMAN.load(Ordering::SeqCst) {
                exit_human("2FA required (set IOS_SIDELLOAD_2FA_CODE or use iLoader)");
            }
            exit_fail(&format!("Apple login failed: {e}"));
        }
    };

    if NEED_HUMAN.load(Ordering::SeqCst) {
        exit_human("2FA required");
    }

    let dev_session = match DeveloperSession::from_account(&mut account).await {
        Ok(s) => s,
        Err(e) => exit_fail(&format!("DeveloperSession: {e}")),
    };

    let mut usbmuxd = match UsbmuxdConnection::default().await {
        Ok(u) => u,
        Err(e) => exit_fail(&format!("usbmuxd: {e}")),
    };
    let devs = match usbmuxd.get_devices().await {
        Ok(d) => d,
        Err(e) => exit_fail(&format!("list devices: {e}")),
    };
    if devs.is_empty() {
        exit_fail("no USB iPhone found");
    }
    let provider =
        devs[0].to_provider(UsbmuxdAddr::from_env_var().unwrap(), "chatbot-isideload");

    let machine = env::var("IOS_SIDELLOAD_MACHINE_NAME")
        .unwrap_or_else(|_| "chatbot-pc".to_string());

    let mut sideloader = SideloaderBuilder::new(dev_session, apple_id.clone())
        .team_selection(TeamSelection::First)
        .max_certs_behavior(MaxCertsBehavior::Revoke)
        .storage(Box::new(FsStorage::new(storage_dir)))
        .machine_name(machine)
        .build();

    match sideloader
        .install_app(
            &provider,
            app_path,
            true,
            None::<fn(f32) -> std::future::Ready<()>>,
        )
        .await
    {
        Ok(_) => {
            println!("OK: app installed via isideload");
            process::exit(0);
        }
        Err(e) => {
            let msg = format!("{e}");
            if msg.to_lowercase().contains("2fa") || msg.contains("Abort") {
                exit_human(&msg);
            }
            exit_fail(&format!("install_app: {msg}"));
        }
    }
}

fn dirs_fallback() -> PathBuf {
    if let Ok(l) = env::var("LOCALAPPDATA") {
        return PathBuf::from(l);
    }
    env::temp_dir()
}
