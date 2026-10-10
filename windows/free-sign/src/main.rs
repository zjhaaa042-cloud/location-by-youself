use idevice::usbmuxd::{UsbmuxdAddr, UsbmuxdConnection};
use isideload::{
    anisette::remote_v3::RemoteV3AnisetteProvider,
    auth::apple_account::{AppleAccount, TwoFactorCallbackParams, TwoFactorCallbackResponse},
    dev::{certificates::DevelopmentCertificate, developer_session::DeveloperSession, teams::DeveloperTeam},
    sideload::{SideloaderBuilder, TeamSelection, builder::MaxCertsBehavior},
    util::keyring_storage::KeyringStorage,
};
use std::{io::{self, Write}, path::PathBuf};

fn prompt(message: &str) -> String {
    print!("{message}");
    let _ = io::stdout().flush();
    let mut line = String::new();
    let _ = io::stdin().read_line(&mut line);
    line.trim().to_string()
}

fn choose_team(teams: &Vec<DeveloperTeam>) -> Option<String> {
    println!("Select the SAME team used for the previous installation:");
    for (i, team) in teams.iter().enumerate() {
        println!("{}: {} ({})", i + 1, team.name.as_deref().unwrap_or("Personal Team"), team.team_id);
    }
    let index = prompt("Team number: ").parse::<usize>().ok()?;
    teams.get(index.checked_sub(1)?).map(|team| team.team_id.clone())
}

#[tokio::main]
async fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 || args[1] == "--help" {
        println!("locationmocker-free-sign <UDID> <IPA> [https://anisette-server]");
        return;
    }
    let result = install(&args).await;
    if result.is_err() {
        eprintln!("FREE_SIGN_FAILED: Check account verification, network, device trust and certificate quota. No certificates were automatically revoked.");
        std::process::exit(1);
    }
    println!("Installation completed. Enable Developer Mode and trust the developer on your iPhone if prompted.");
}

async fn install(args: &[String]) -> Result<(), Box<dyn std::error::Error>> {
    let _ = rustls::crypto::ring::default_provider().install_default();
    isideload::init().map_err(|_| "Initialization failed")?;
    let udid = &args[1];
    let ipa = PathBuf::from(&args[2]);
    if !ipa.is_file() { return Err("IPA not found".into()); }
    // Resolve the explicit device before asking for account credentials.
    let mut mux = UsbmuxdConnection::default().await?;
    let device = mux.get_device(udid).await?;
    let provider = device.to_provider(UsbmuxdAddr::from_env_var()?, "locationmocker-free-sign");
    let email = prompt("Apple ID: ");
    let password = rpassword::prompt_password("Apple ID password (not saved): ")?;
    let mut anisette = RemoteV3AnisetteProvider::default().map_err(|_| "Anisette initialization failed")?
        .set_storage(Box::new(KeyringStorage::new("LocationMocker-FreeSign".to_string())));
    if let Some(url) = args.get(3) {
        if !url.starts_with("https://") { return Err("Anisette requires HTTPS".into()); }
        anisette = anisette.set_url(url);
    }
    let two_factor = async |params: TwoFactorCallbackParams| {
        println!("Enter verification code. d = trusted devices, r = resend, p<ID> = SMS.");
        for number in &params.numbers {
            println!("p{}: {}", number.id, number.number_with_dial_code);
        }
        let answer = rpassword::prompt_password("Verification: ").unwrap_or_default();
        let answer = answer.trim();
        if answer == "d" { return Ok(TwoFactorCallbackResponse::SendToDevices); }
        if answer == "r" && !params.unknown { return Ok(TwoFactorCallbackResponse::ResendCode); }
        if let Some(id) = answer.strip_prefix('p').and_then(|s| s.parse::<u32>().ok()) {
            if params.numbers.iter().any(|n| n.id == id) { return Ok(TwoFactorCallbackResponse::SendSms(id)); }
        }
        Ok(TwoFactorCallbackResponse::SubmitCode(answer.to_string()))
    };
    println!("Signing in to Apple…");
    let mut account = AppleAccount::builder(&email).anisette_provider(anisette)
        .login(&password, two_factor).await.map_err(|_| "Apple login failed")?;
    drop(password);
    let session = DeveloperSession::from_account(&mut account).await.map_err(|_| "Developer session failed")?;
    let refuse_revocation = async |_certs: Vec<DevelopmentCertificate>| {
        println!("Certificate quota reached. Manage existing certificates in your signing tool, then retry.");
        Ok(None)
    };
    let mut sideloader = SideloaderBuilder::new(session, email)
        .team_selection(TeamSelection::PromptOnce(choose_team))
        .max_certs_behavior(MaxCertsBehavior::Prompt(refuse_revocation))
        .storage(Box::new(KeyringStorage::new("LocationMocker-FreeSign".to_string())))
        .machine_name("LocationMocker Windows".to_string()).build();
    println!("Registering device, obtaining profile, signing and installing…");
    sideloader.install_app(&provider, ipa, false, None::<fn(f32) -> std::future::Ready<()>>, None)
        .await.map_err(|_| "Signing or installation failed")?;
    Ok(())
}
