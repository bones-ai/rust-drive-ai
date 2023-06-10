use bevy::{
    diagnostic::{FrameTimeDiagnosticsPlugin, LogDiagnosticsPlugin},
    math::vec3,
    prelude::*,
    window::{PresentMode, WindowMode},
};
use bevy_inspector_egui::{bevy_egui::EguiPlugin, DefaultInspectorConfigPlugin};
use bevy_pancam::{PanCam, PanCamPlugin};
use bevy_rapier2d::{
    prelude::{Collider, NoUserData, RapierConfiguration, RapierPhysicsPlugin, RigidBody},
    render::RapierDebugRenderPlugin,
};

use steering::{
    car::{Car, CarPlugin},
    gui::GuiPlugin,
    population::PopulationPlugin,
};
use steering::{
    enemy::{spawn_bound_trucks, EnemyPlugin},
    *,
};

fn main() {
    App::new()
        .add_plugins(
            DefaultPlugins
                .set(ImagePlugin::default_nearest())
                .set(WindowPlugin {
                    primary_window: Some(Window {
                        resizable: false,
                        // mode: WindowMode::Fullscreen,
                        focused: true,
                        // present_mode: PresentMode::Immediate,
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
