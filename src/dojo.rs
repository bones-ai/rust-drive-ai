use bevy::log;
use bevy::prelude::*;
use bevy_tokio_tasks::{TokioTasksPlugin, TokioTasksRuntime};
use dojo_client::contract::component::ComponentReader;
use dojo_client::contract::system::System;
use dojo_client::contract::world::WorldContract;
use eyre::Result;
use starknet::accounts::Account;
use starknet::accounts::SingleOwnerAccount;
use starknet::core::types::{BlockId, BlockTag, FieldElement};
use starknet::core::utils::cairo_short_string_to_felt;
use starknet::providers::jsonrpc::HttpTransport;
use starknet::providers::JsonRpcClient;
use starknet::signers::{LocalWallet, SigningKey};
use std::str::FromStr;
use tokio::sync::mpsc;
use url::Url;

use crate::configs;

pub struct DojoPlugin;

impl Plugin for DojoPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugin(TokioTasksPlugin::default())
            .add_startup_systems((setup, spawn_sync_thread))
            .add_system(time_to_sync);
    }
}

fn setup(mut commands: Commands) {
    commands.spawn(DojoSyncTime::from_seconds(configs::DOJO_SYNC_INTERVAL));
}

#[derive(Component)]
struct DojoSyncTime {
    timer: Timer,
}

impl DojoSyncTime {
    fn from_seconds(duration: f32) -> Self {
        Self {
            timer: Timer::from_seconds(duration, TimerMode::Repeating),
        }
    }
}

fn time_to_sync(
    mut dojo_sync_time: Query<&mut DojoSyncTime>,
    time: Res<Time>,
    sender: Query<&DojoSyncSender>,
) {
    if let Ok(sender) = sender.get_single() {
        let mut dojo_time = dojo_sync_time.single_mut();

        if dojo_time.timer.just_finished() {
            dojo_time.timer.reset();

            match sender.inner.try_send(DojoSyncMessage) {
                Ok(_) => {}
                Err(e) => {
                    log::error!("{e}");
                }
            }
        } else {
            dojo_time.timer.tick(time.delta());
        }
    }
}

fn spawn_sync_thread(runtime: ResMut<TokioTasksRuntime>, mut commands: Commands) {
    // Create channel
    let (tx, mut rx) = mpsc::channel::<DojoSyncMessage>(8);
    commands.spawn(DojoSyncSender { inner: tx });

    runtime.spawn_background_task(|_ctx| async move {
        // Get world contract
        let url = Url::parse(configs::JSON_RPC_ENDPOINT).unwrap();
        let account_address = FieldElement::from_str(configs::ACCOUNT_ADDRESS).unwrap();
        let account = SingleOwnerAccount::new(
            JsonRpcClient::new(HttpTransport::new(url)),
            LocalWallet::from_signing_key(SigningKey::from_secret_scalar(
                FieldElement::from_str(configs::ACCOUNT_SECRET_KEY).unwrap(),
            )),
            account_address,
            cairo_short_string_to_felt("KATANA").unwrap(),
        );

        let world_address = FieldElement::from_str(configs::WORLD_ADDRESS).unwrap();
        let block_id = BlockId::Tag(BlockTag::Latest);
        let world = WorldContract::new(world_address, &account);

        // Components
        let vehicle_component = world.component("Vehicle", block_id).await.unwrap();

        // Systems
        let spawn_racer_system = world.system("spawn_racer", block_id).await.unwrap();
        let drive_system = world.system("drive", block_id).await.unwrap();

        // Spawn cars
        let mut racer_ids = vec![];
        for i in 0..configs::NUM_AI_CARS {
            let racer_id = FieldElement::from_hex_be(&format!("0x{}", i)).unwrap();
            racer_ids.push(racer_id);
            spawn_racer_system.execute(vec![racer_id]).await.unwrap();
        }

        while let Some(_msg) = rx.recv().await {
            if let Err(e) = sync(
                &world,
                &vehicle_component,
                &drive_system,
                &racer_ids,
                block_id,
            )
            .await
            {
                log::error!("{e}");
            }
        }
    });
}

async fn sync<'a>(
    world: &WorldContract<'_, SingleOwnerAccount<JsonRpcClient<HttpTransport>, LocalWallet>>,
    vehicle_component: &ComponentReader<'_, JsonRpcClient<HttpTransport>>,
    drive_system: &System<'_, SingleOwnerAccount<JsonRpcClient<HttpTransport>, LocalWallet>>,
    racer_ids: &Vec<FieldElement>,
    block_id: BlockId,
) -> Result<()> {
    log::info!("tick");

    // Update car position
    let vehicle = vehicle_component
        .entity(FieldElement::ZERO, vec![racer_ids[0]], block_id)
        .await?;

    log::info!("{vehicle:#?}");
    // log::info!("x: mag: {}, sign: {}", vehicle[0], vehicle[1]);
    // log::info!("y: mag: {}, sign: {}", vehicle[2], vehicle[3]);

    // Call derive system to move forward
    for id in racer_ids {
        drive_system.execute(vec![*id]).await?;
    }

    Ok(())
}

struct DojoSyncMessage;

#[derive(Component)]
struct DojoSyncSender {
    inner: mpsc::Sender<DojoSyncMessage>,
}
