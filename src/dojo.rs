use crate::car::Car;
use crate::car::CarBundle;
use crate::configs;
use bevy::ecs::system::SystemState;
use bevy::log;
use bevy::prelude::*;
use bevy_tokio_tasks::{TokioTasksPlugin, TokioTasksRuntime};
use bigdecimal::ToPrimitive;
use dojo_client::contract::world::WorldContract;
use starknet::accounts::SingleOwnerAccount;
use starknet::core::types::{BlockId, BlockTag, FieldElement};
use starknet::core::utils::cairo_short_string_to_felt;
use starknet::providers::jsonrpc::HttpTransport;
use starknet::providers::JsonRpcClient;
use starknet::signers::{LocalWallet, SigningKey};
use std::str::FromStr;
use tokio::sync::mpsc;
use url::Url;

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
    sender: Res<DojoSyncSender>,
) {
    let mut dojo_time = dojo_sync_time.single_mut();

    if dojo_time.timer.just_finished() {
        dojo_time.timer.reset();

        if let Err(e) = sender.inner.try_send(DojoSyncMessage::UpdatePosition) {
            log::error!("{e}");
        }
        if let Err(e) = sender.inner.try_send(DojoSyncMessage::Drive) {
            log::error!("{e}");
        }
    } else {
        dojo_time.timer.tick(time.delta());
    }
}

fn spawn_sync_thread(runtime: ResMut<TokioTasksRuntime>, mut commands: Commands) {
    // Create channel
    let (tx, mut rx) = mpsc::channel::<DojoSyncMessage>(8);
    commands.insert_resource(DojoSyncSender { inner: tx });

    runtime.spawn_background_task(|mut ctx| async move {
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

        // TODO: Can it be added as Resource or Component? If yes, we don't need the mpsc channel.
        let world = WorldContract::new(world_address, &account);

        // Components
        let vehicle_component = world.component("Vehicle", block_id).await.unwrap();

        // Systems
        let spawn_racer_system = world.system("spawn_racer", block_id).await.unwrap();
        let drive_system = world.system("drive", block_id).await.unwrap();

        while let Some(msg) = rx.recv().await {
            log::info!("Start listening to dojo sync messages");

            match msg {
                DojoSyncMessage::SpawnCars => {
                    let mut dojo_ids = vec![];
                    for i in 0..configs::NUM_AI_CARS {
                        let dojo_id = FieldElement::from_dec_str(&i.to_string()).unwrap();

                        dojo_ids.push(dojo_id);

                        match spawn_racer_system.execute(vec![dojo_id]).await {
                            Ok(_) => {
                                ctx.run_on_main_thread(move |ctx| {
                                    let asset_server =
                                        ctx.world.get_resource::<AssetServer>().unwrap();
                                    ctx.world.spawn(CarBundle::new(&asset_server, dojo_id));
                                })
                                .await;
                            }
                            Err(e) => {
                                log::error!("Failed to call spawn_racer system: {e}");
                            }
                        }
                    }
                }
                DojoSyncMessage::Drive => {
                    let dojo_ids = ctx
                        .run_on_main_thread(move |ctx| {
                            let mut state: SystemState<Query<&Car>> = SystemState::new(ctx.world);
                            let query = state.get(ctx.world);

                            query
                                .iter()
                                .map(|car| car.dojo_id)
                                .collect::<Vec<FieldElement>>()
                        })
                        .await;

                    for dojo_id in dojo_ids.iter() {
                        if let Err(e) = drive_system.execute(vec![*dojo_id]).await {
                            log::error!("Failed to call drive system: {e}");
                        }
                    }
                }
                DojoSyncMessage::UpdatePosition => {
                    let dojo_ids = ctx
                        .run_on_main_thread(move |ctx| {
                            let mut state: SystemState<Query<&Car>> = SystemState::new(ctx.world);
                            let query = state.get(ctx.world);

                            query
                                .iter()
                                .map(|car| car.dojo_id)
                                .collect::<Vec<FieldElement>>()
                        })
                        .await;

                    for dojo_id in dojo_ids.iter() {
                        if let Err(e) = drive_system.execute(vec![*dojo_id]).await {
                            log::error!("Failed to execute drive system: {e}");
                        }

                        match vehicle_component
                            .entity(FieldElement::ZERO, vec![*dojo_id], block_id)
                            .await
                        {
                            Ok(vehicle) => {
                                // log::info!("{vehicle:#?}");
                                log::info!(
                                    "x: {}, y: {}",
                                    vehicle[0].to_string().parse::<f32>().unwrap(),
                                    vehicle[2].to_string().parse::<f32>().unwrap()
                                );
                                ctx.run_on_main_thread(move |ctx| {
                                    let mut state: SystemState<Query<&mut Transform, With<Car>>> =
                                        SystemState::new(ctx.world);
                                    let mut query = state.get_mut(ctx.world);
                                    for mut transform in query.iter_mut() {
                                        transform.translation.y = configs::WINDOW_HEIGHT / 2.00
                                            + vehicle[2].to_big_decimal(19).to_f32().unwrap();
                                    }
                                })
                                .await;
                            }
                            Err(e) => {
                                log::error!("Failed to query vehicle component: {e}");
                            }
                        }
                    }
                }
            }
        }
    });
}

pub enum DojoSyncMessage {
    SpawnCars,
    Drive,
    UpdatePosition,
}

#[derive(Resource)]
pub struct DojoSyncSender {
    inner: mpsc::Sender<DojoSyncMessage>,
}

impl DojoSyncSender {
    pub fn try_send(
        &self,
        message: DojoSyncMessage,
    ) -> Result<(), tokio::sync::mpsc::error::TrySendError<DojoSyncMessage>> {
        self.inner.try_send(message)
    }
}
