use bevy::log;
use bevy::tasks::{AsyncComputeTaskPool, Task};
use bevy::{math::vec3, prelude::*};
use bevy_inspector_egui::{bevy_egui::EguiPlugin, DefaultInspectorConfigPlugin};
use bevy_pancam::{PanCam, PanCamPlugin};
use bevy_rapier2d::prelude::{
    Collider, NoUserData, RapierConfiguration, RapierPhysicsPlugin, RigidBody,
};
use dojo_client::contract::world::WorldContractReader;
// use eyre::{bail, Result};
use starknet::accounts::ConnectedAccount;
use starknet::accounts::SingleOwnerAccount;
use starknet::core::chain_id;
use starknet::core::types::{BlockId, BlockTag, FieldElement};
use starknet::providers::jsonrpc::HttpTransport;
use starknet::providers::JsonRpcClient;
use starknet::signers::{LocalWallet, SigningKey};
use std::str::FromStr;
use steering::{
    car::{Car, CarPlugin},
    gui::GuiPlugin,
    population::PopulationPlugin,
};
use steering::{
    enemy::{spawn_bound_trucks, EnemyPlugin},
    *,
};
use url::Url;

fn main() {
    App::new()
        .insert_resource(FixedTime::new_from_secs(0.25))
        .add_plugins(
            DefaultPlugins
                .set(ImagePlugin::default_nearest())
                .set(WindowPlugin {
                    primary_window: Some(Window {
                        resizable: false,
                        focused: true,
                        resolution: (WINDOW_WIDTH, WINDOW_HEIGHT).into(),
                        ..default()
                    }),
                    ..default()
                }),
        )
        .add_plugin(PanCamPlugin::default())
        // .add_plugin(WorldInspectorPlugin::new().run_if(input_toggle_active(false, KeyCode::Tab))) // remove eguiplugin
        .add_plugin(DefaultInspectorConfigPlugin) // Requires egui plugin
        .add_plugin(EguiPlugin)
        .add_plugin(RapierPhysicsPlugin::<NoUserData>::pixels_per_meter(100.0))
        // .add_plugin(LogDiagnosticsPlugin::default())
        // .add_plugin(FrameTimeDiagnosticsPlugin::default())
        .add_plugin(CarPlugin)
        .add_plugin(EnemyPlugin)
        .add_plugin(PopulationPlugin)
        .add_plugin(GuiPlugin)
        .add_plugin(DojoPlugin)
        // .add_plugin(RapierDebugRenderPlugin::default())
        .insert_resource(ClearColor(Color::rgb_u8(36, 36, 36)))
        // .insert_resource(ClearColor(Color::WHITE))
        // .insert_resource(Msaa::Off)
        .add_startup_system(setup)
        .add_system(bevy::window::close_on_esc)
        .add_system(camera_follow_system)
        .add_system(settings_system)
        .run();
}

fn setup(
    mut commands: Commands,
    asset_server: Res<AssetServer>,
    mut rapier_config: ResMut<RapierConfiguration>,
) {
    rapier_config.gravity = Vec2::ZERO;

    commands
        .spawn(Camera2dBundle {
            transform: Transform::from_xyz(WINDOW_WIDTH / 2.0, WINDOW_HEIGHT / 2.0, 0.0),
            ..default()
        })
        .insert(PanCam::default());

    spawn_roads(&mut commands, &asset_server);
    spawn_bound_trucks(&mut commands, &asset_server);
}

fn camera_follow_system(
    settings: Res<Settings>,
    max_distance_travelled: Res<MaxDistanceTravelled>,
    mut cam_query: Query<(&Camera, &mut Transform), Without<Car>>,
) {
    let (_, mut cam_transform) = cam_query.get_single_mut().unwrap();
    if settings.is_camera_follow {
        cam_transform.translation = cam_transform.translation.lerp(
            vec3(cam_transform.translation.x, max_distance_travelled.0, 0.0),
            0.05,
        );
    }
}

fn spawn_roads(commands: &mut Commands, asset_server: &AssetServer) {
    // Road
    let rx = WINDOW_WIDTH / 2.0 - 30.0;
    let mut ry = ROAD_SPRITE_H / 2.0 * SPRITE_SCALE_FACTOR;
    for _ in 0..NUM_ROAD_TILES {
        commands.spawn(SpriteBundle {
            transform: Transform::from_xyz(rx, ry, -10.0)
                .with_scale(Vec3::splat(SPRITE_SCALE_FACTOR)),
            texture: asset_server.load("road.png"),
            ..default()
        });
        ry += ROAD_SPRITE_H * SPRITE_SCALE_FACTOR;
    }
    let road_end_y = ry - ROAD_SPRITE_H * SPRITE_SCALE_FACTOR + 800.0;

    // end checker board
    commands.spawn(SpriteBundle {
        transform: Transform::from_xyz(rx, road_end_y - 50.0, -5.0)
            .with_scale(Vec3::splat(SPRITE_SCALE_FACTOR)),
        texture: asset_server.load("end-point.png"),
        ..default()
    });

    // Road colliders
    // left
    let ry = 5.0 * ROAD_SPRITE_H * SPRITE_SCALE_FACTOR;
    let rx_min = ROAD_SPRITE_W / 2.0 * SPRITE_SCALE_FACTOR + 238.0;
    commands.spawn((
        SpriteBundle {
            transform: Transform::from_xyz(rx_min, ry, 0.0).with_scale(vec3(0.5, 0.5, 1.0)),
            ..default()
        },
        RigidBody::Fixed,
        Collider::cuboid(
            5.0,
            ROAD_SPRITE_H * SPRITE_SCALE_FACTOR * NUM_ROAD_TILES as f32 * 5.0,
        ),
    ));
    // right
    let rx_max = ROAD_SPRITE_W * SPRITE_SCALE_FACTOR + 248.0;
    commands.spawn((
        SpriteBundle {
            transform: Transform::from_xyz(rx_max, ry, 0.0).with_scale(vec3(0.5, 0.5, 1.0)),
            ..default()
        },
        RigidBody::Fixed,
        Collider::cuboid(
            5.0,
            ROAD_SPRITE_H * SPRITE_SCALE_FACTOR * NUM_ROAD_TILES as f32 * 5.0,
        ),
    ));
    // top
    commands.spawn((
        SpriteBundle {
            transform: Transform::from_xyz(600.0, road_end_y, 0.0).with_scale(vec3(0.5, 0.5, 1.0)),
            ..default()
        },
        RigidBody::Fixed,
        Collider::cuboid(500.0 * SPRITE_SCALE_FACTOR, 10.0),
    ));
}

fn settings_system(
    mut commands: Commands,
    mut settings: ResMut<Settings>,
    mut sim_stats: ResMut<SimStats>,
    car_query: Query<Entity, With<Car>>,
) {
    if settings.start_next_generation {
        settings.start_next_generation = false;
        car_query.iter().for_each(|c| {
            commands.entity(c).remove::<Car>();
        });
    }
    if settings.restart_sim {
        // force restart
        car_query.iter().for_each(|c| {
            commands.entity(c).remove::<Car>();
        });
        *sim_stats = SimStats::default();
        sim_stats.generation_count = 0;
    }
}

struct DojoPlugin;

impl Plugin for DojoPlugin {
    fn build(&self, app: &mut App) {
        app.add_event::<PollWorldState>()
            .add_startup_system(setup_dojo)
            .add_system(poll_world);
        // .add_systems((time_to_sync, poll_world));
    }
}

fn setup_dojo(mut poll_event: EventWriter<PollWorldState>) {
    poll_event.send(PollWorldState);
}

// fn setup_dojo(mut commands: Commands) {
//     commands.spawn(DojoSyncTime::from_seconds(1.00));
// }

// #[derive(Component)]
// struct DojoSyncTime {
//     timer: Timer,
// }

// impl DojoSyncTime {
//     fn from_seconds(duration: f32) -> Self {
//         Self {
//             timer: Timer::from_seconds(duration, TimerMode::Repeating),
//         }
//     }
// }

// fn time_to_sync(
//     mut q: Query<&mut DojoSyncTime>,
//     time: Res<Time>,
//     mut poll_event: EventWriter<PollWorldState>,
// ) {
//     let mut dojo_time = q.single_mut();

//     if dojo_time.timer.just_finished() {
//         dojo_time.timer.reset();

//         poll_event.send(PollWorldState);
//     } else {
//         dojo_time.timer.tick(time.delta());
//     }
// }

struct PollWorldState;

#[derive(Component)]
struct PollTask(Task<()>);

fn poll_world(mut events: EventReader<PollWorldState>, mut commands: Commands) {
    events.iter().for_each(|_| {
        log::info!("TODO: poll world state!");

        let thread_pool = AsyncComputeTaskPool::get();
        let task = thread_pool.spawn(async move {
            // TODO: create startup system to create world
            let url = Url::parse("http://0.0.0.0:5050").expect("Failed to parse URL");
            let account_address = FieldElement::from_str(
                "0x03ee9e18edc71a6df30ac3aca2e0b02a198fbce19b7480a63a0d71cbd76652e0",
            )
            .unwrap();
            let account = SingleOwnerAccount::new(
                JsonRpcClient::new(HttpTransport::new(url)),
                LocalWallet::from_signing_key(SigningKey::from_secret_scalar(
                    FieldElement::from_str(
                        "0x0300001800000000300000180000000000030000000000003006001800006600",
                    )
                    .unwrap(),
                )),
                account_address,
                chain_id::TESTNET,
            );
            let world = WorldContractReader::new(
                FieldElement::from_str(
                    "0x7d17bb24b59cb371c9ca36b79efca27fe53318e26340df3d8623dba5a7b9e5f",
                )
                .unwrap(),
                account.provider(),
            );

            let block_id = BlockId::Tag(BlockTag::Latest);
            let component = world.component("Moves", block_id).await.unwrap();
            let moves = component
                .entity(FieldElement::ZERO, vec![account_address], block_id)
                .await
                .unwrap();

            log::info!("{:#?}", moves);
        });

        commands.spawn(PollTask(task));
    });
}
