use crate::car::Car;
use crate::car::CarBundle;
use crate::configs;
use crate::enemy::Enemy;
use crate::enemy::EnemyId;
use crate::enemy::EnemyType;
use crate::ROAD_X_MIN;
use bevy::ecs::system::SystemState;
use bevy::log;
use bevy::math::vec3;
use bevy::prelude::*;
use bevy_rapier2d::prelude::ActiveEvents;
use bevy_rapier2d::prelude::Collider;
use bevy_rapier2d::prelude::ColliderMassProperties;
use bevy_rapier2d::prelude::Damping;
use bevy_rapier2d::prelude::Friction;
use bevy_rapier2d::prelude::RigidBody;
use bevy_rapier2d::prelude::Velocity;
use bevy_tokio_tasks::TaskContext;
use bevy_tokio_tasks::{TokioTasksPlugin, TokioTasksRuntime};
use dojo_client::contract::world::WorldContract;
use num::bigint::BigUint;
use num::{FromPrimitive, ToPrimitive};
use rand::Rng;
use starknet::accounts::SingleOwnerAccount;
use starknet::core::types::{BlockId, BlockTag, FieldElement};
use starknet::core::utils::cairo_short_string_to_felt;
use starknet::providers::jsonrpc::HttpTransport;
use starknet::providers::JsonRpcClient;
use starknet::signers::{LocalWallet, SigningKey};
use std::ops::Div;
use std::str::FromStr;
use std::sync::Arc;
use tokio::sync::mpsc;
use url::Url;

pub fn rand_felt_fixed_point() -> FieldElement {
    let mut rng = rand::thread_rng();
    ((rng.gen::<u128>() % 200) << 64).into()
}

#[derive(Resource)]
pub struct DojoEnv {
    /// The block ID to use for all contract calls.
    block_id: BlockId,
    /// The address of the world contract.
    world_address: FieldElement,
    /// The account to use for performing execution on the World contract.
    account: Arc<SingleOwnerAccount<JsonRpcClient<HttpTransport>, LocalWallet>>,
}

impl DojoEnv {
    fn new(
        world_address: FieldElement,
        account: SingleOwnerAccount<JsonRpcClient<HttpTransport>, LocalWallet>,
    ) -> Self {
        Self {
            world_address,
            account: Arc::new(account),
            block_id: BlockId::Tag(BlockTag::Latest),
        }
    }
}

#[derive(Resource, Default)]
pub struct Model {
    id: FieldElement,
}

pub struct DojoPlugin;

impl Plugin for DojoPlugin {
    fn build(&self, app: &mut App) {
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

        app.add_plugin(TokioTasksPlugin::default())
            .insert_resource(DojoEnv::new(world_address, account))
            .init_resource::<Model>()
            .add_startup_systems((
                setup,
                spawn_racers_thread,
                drive_thread,
                update_vehicle_thread,
                update_enemies_thread,
            ))
            .add_system(sync_dojo_state);
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

fn sync_dojo_state(
    mut dojo_sync_time: Query<&mut DojoSyncTime>,
    time: Res<Time>,
    drive: Res<DriveCommand>,
    update_vehicle: Res<UpdateVehicleCommand>,
    update_enemies: Res<UpdateEnemiesCommand>,
) {
    let mut dojo_time = dojo_sync_time.single_mut();

    if dojo_time.timer.just_finished() {
        dojo_time.timer.reset();

        if let Err(e) = update_vehicle.try_send() {
            log::error!("{e}");
        }
        // if let Err(e) = drive.try_send() {
        //     log::error!("{e}");
        // }
        if let Err(e) = update_enemies.try_send() {
            log::error!("{e}");
        }
    } else {
        dojo_time.timer.tick(time.delta());
    }
}

fn spawn_racers_thread(
    env: Res<DojoEnv>,
    runtime: ResMut<TokioTasksRuntime>,
    mut commands: Commands,
) {
    let (tx, mut rx) = mpsc::channel::<()>(8);
    commands.insert_resource(SpawnRacersCommand(tx));

    let account = env.account.clone();
    let world_address = env.world_address;
    let block_id = env.block_id;

    runtime.spawn_background_task(move |mut ctx| async move {
        let world = WorldContract::new(world_address, account.as_ref());
        let spawn_racer_system = world.system("spawn_racer", block_id).await.unwrap();

        while let Some(_) = rx.recv().await {
            let model_id: FieldElement = 0_u8.into();

            match spawn_racer_system
                .execute(vec![
                    model_id,
                    rand_felt_fixed_point(),
                    FieldElement::ZERO,
                    FieldElement::ZERO,
                    FieldElement::ZERO,
                ])
                .await
            {
                Ok(_) => {
                    ctx.run_on_main_thread(move |ctx| {
                        let asset_server = ctx.world.get_resource::<AssetServer>().unwrap();
                        ctx.world.spawn(CarBundle::new(&asset_server, model_id));
                    })
                    .await;

                    ctx.run_on_main_thread(move |ctx| {
                        for id in 0..configs::DOJO_ENEMIES_NB {
                            let asset_server = ctx.world.get_resource::<AssetServer>().unwrap();

                            let enemy_type = EnemyType::random();
                            let enemy_scale = match enemy_type {
                                EnemyType::Truck => 3.0,
                                _ => 2.5,
                            };
                            let collider = match enemy_type {
                                EnemyType::Truck => Collider::cuboid(6.0, 15.0),
                                _ => Collider::cuboid(4.0, 8.0),
                            };

                            ctx.world.spawn((
                                SpriteBundle {
                                    // TODO: workaround: spawn outside of screen because we know all enermies are spawned but don't know their positions yet
                                    transform: Transform::from_xyz(1000.0, 1000.0, 0.0)
                                        .with_scale(vec3(enemy_scale, enemy_scale, 1.0)),
                                    texture: asset_server.load(enemy_type.get_sprite()),
                                    ..default()
                                },
                                RigidBody::Dynamic,
                                Velocity::zero(),
                                ColliderMassProperties::Mass(1.0),
                                Friction::new(100.0),
                                ActiveEvents::COLLISION_EVENTS,
                                collider,
                                Damping {
                                    angular_damping: 2.0,
                                    linear_damping: 2.0,
                                },
                                Enemy { is_hit: false },
                                EnemyId(id.into()),
                                enemy_type,
                            ));
                        }
                    })
                    .await;
                }
                Err(e) => {
                    log::error!("Run spawn_racer system: {e}");
                }
            }
        }
    });
}

fn drive_thread(
    env: Res<DojoEnv>,
    model: Res<Model>,
    runtime: ResMut<TokioTasksRuntime>,
    mut commands: Commands,
) {
    let (tx, mut rx) = mpsc::channel::<()>(8);
    commands.insert_resource(DriveCommand(tx));

    let account = env.account.clone();
    let world_address = env.world_address;
    let block_id = env.block_id;
    let model_id = model.id;

    runtime.spawn_background_task(move |_| async move {
        let world = WorldContract::new(world_address, account.as_ref());

        let drive_system = world.system("drive", block_id).await.unwrap();

        while let Some(_) = rx.recv().await {
            if let Err(e) = drive_system.execute(vec![model_id]).await {
                log::error!("Run drive system: {e}");
            }
        }
    });
}

fn update_vehicle_thread(
    env: Res<DojoEnv>,
    model: Res<Model>,
    runtime: ResMut<TokioTasksRuntime>,
    mut commands: Commands,
) {
    let (tx, mut rx) = mpsc::channel::<()>(8);
    commands.insert_resource(UpdateVehicleCommand(tx));

    let account = env.account.clone();
    let world_address = env.world_address;
    let block_id = env.block_id;
    let model_id = model.id;

    runtime.spawn_background_task(move |mut ctx| async move {
        let world = WorldContract::new(world_address, account.as_ref());
        let vehicle_component = world.component("Vehicle", block_id).await.unwrap();

        while let Some(_) = rx.recv().await {
            match vehicle_component
                .entity(FieldElement::ZERO, vec![model_id], block_id)
                .await
            {
                Ok(vehicle) => {
                    // log::info!("{vehicle:#?}");

                    let (new_x, new_y) =
                        dojo_to_bevy_coordinate(fixed_to_f32(vehicle[0]), fixed_to_f32(vehicle[2]));

                    log::info!("Vehicle Position ({model_id}), x: {new_x}, y: {new_y}");

                    ctx.run_on_main_thread(move |ctx| {
                        let mut state: SystemState<Query<&mut Transform, With<Car>>> =
                            SystemState::new(ctx.world);
                        let mut query = state.get_mut(ctx.world);

                        if let Ok(mut transform) = query.get_single_mut() {
                            transform.translation.x = new_x;
                            transform.translation.y = new_y;
                        }
                    })
                    .await
                }
                Err(e) => {
                    log::error!("Query `Vehicle` component: {e}");
                }
            }
        }
    });
}

fn update_enemies_thread(
    env: Res<DojoEnv>,
    model: Res<Model>,
    runtime: ResMut<TokioTasksRuntime>,
    mut commands: Commands,
) {
    let (tx, mut rx) = mpsc::channel::<()>(8);
    commands.insert_resource(UpdateEnemiesCommand(tx));

    let account = env.account.clone();
    let world_address = env.world_address;
    let block_id = env.block_id;
    let model_id = model.id;

    runtime.spawn_background_task(move |mut ctx| async move {
        let world = WorldContract::new(world_address, account.as_ref());
        let position_component = world.component("Position", block_id).await.unwrap();

        while let Some(_) = rx.recv().await {
            for i in 0..configs::DOJO_ENEMIES_NB {
                let enemy_id: FieldElement = i.into();

                match position_component
                    .entity(
                        FieldElement::ZERO,
                        vec![model_id, enemy_id.into()],
                        block_id,
                    )
                    .await
                {
                    Ok(position) => {
                        // TODO: Why it's always x: 0, y: 0,
                        // log::info!("{position:#?}");

                        let (new_x, new_y) = dojo_to_bevy_coordinate(
                            position[0].to_string().parse().unwrap(),
                            position[1].to_string().parse().unwrap(),
                        );

                        // TODO: multiply by dojo_to_bevy coordinate ratio

                        log::info!("Enermy Position ({enemy_id}), x: {new_x}, y: {new_y}");

                        ctx.run_on_main_thread(move |ctx| {
                            let mut state: SystemState<
                                Query<(&mut Transform, &EnemyId), With<Enemy>>,
                            > = SystemState::new(ctx.world);
                            let mut query = state.get_mut(ctx.world);
                            for (mut transform, enemy_id_comp) in query.iter_mut() {
                                if enemy_id_comp.0 == enemy_id {
                                    transform.translation.x = new_x;
                                    transform.translation.y = new_y;
                                }
                            }
                        })
                        .await
                    }
                    Err(e) => {
                        log::error!("Query `Position` component: {e}");
                    }
                }
            }
        }
    });
}

#[derive(Resource)]
pub struct SpawnRacersCommand(mpsc::Sender<()>);

// TODO: derive macro?
impl SpawnRacersCommand {
    pub fn try_send(&self) -> Result<(), mpsc::error::TrySendError<()>> {
        self.0.try_send(())
    }
}

#[derive(Resource)]
struct DriveCommand(mpsc::Sender<()>);

// TODO: derive macro?
impl DriveCommand {
    fn try_send(&self) -> Result<(), mpsc::error::TrySendError<()>> {
        self.0.try_send(())
    }
}

#[derive(Resource)]
struct UpdateVehicleCommand(mpsc::Sender<()>);

impl UpdateVehicleCommand {
    fn try_send(&self) -> Result<(), mpsc::error::TrySendError<()>> {
        self.0.try_send(())
    }
}

#[derive(Resource)]
pub struct UpdateEnemiesCommand(mpsc::Sender<()>);

impl UpdateEnemiesCommand {
    pub fn try_send(&self) -> Result<(), mpsc::error::TrySendError<()>> {
        self.0.try_send(())
    }
}

async fn update_position<T>(mut ctx: TaskContext, x: f32, y: f32)
where
    T: Component,
{
    ctx.run_on_main_thread(move |ctx| {
        let mut state: SystemState<Query<&mut Transform, With<T>>> = SystemState::new(ctx.world);
        let mut query = state.get_mut(ctx.world);

        if let Ok(mut transform) = query.get_single_mut() {
            transform.translation.x = x;
            transform.translation.y = y;
        }
    })
    .await
}

fn fixed_to_f32(val: FieldElement) -> f32 {
    BigUint::from_str(&val.to_string())
        .unwrap()
        .div(BigUint::from_i8(2).unwrap().pow(64))
        .to_f32()
        .unwrap()
}

fn dojo_to_bevy_coordinate(dojo_x: f32, dojo_y: f32) -> (f32, f32) {
    let bevy_x = dojo_x * configs::DOJO_TO_BEVY_RATIO_X + ROAD_X_MIN;
    let bevy_y = dojo_y * configs::DOJO_TO_BEVY_RATIO_Y;

    // log::info!("dojo_x: {}, dojo_y: {}", dojo_x, dojo_y);
    // log::info!("bevy_x: {}, bevy_y: {}", bevy_x, bevy_y);

    (bevy_x, bevy_y)
}
