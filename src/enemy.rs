use bevy::{
    math::{vec2, vec3},
    prelude::*,
};
use bevy_rapier2d::prelude::*;
use rand::{thread_rng, Rng};

use crate::*;

pub struct EnemyPlugin;

#[derive(Component, Reflect, Default)]
pub struct Enemy {
    is_hit: bool,
}

#[derive(Clone, Component, Reflect)]
pub enum EnemyType {
    Simple,
    Horizontal(f32),
    Truck,
}

#[derive(Component)]
pub struct BoundControlTruck;

impl Plugin for EnemyPlugin {
    fn build(&self, app: &mut App) {
        app.add_startup_system(setup)
            .add_system(update_enemies)
            .add_system(bound_control_system);
    }
}

fn setup(mut commands: Commands, asset_server: Res<AssetServer>) {
    spawn_enemies(&mut commands, &asset_server);
}

fn update_enemies(
    mut enemy_query: Query<
        (&mut Transform, &mut Velocity, &mut Enemy, &mut EnemyType),
        With<Enemy>,
    >,
) {
    for (mut transform, mut velocity, mut enemy, mut enemy_type) in enemy_query.iter_mut() {
        if enemy.is_hit {
            continue;
        }

        velocity.linvel = vec2(0.0, 50.0);
        enemy.is_hit = velocity.angvel != 0.0;

        // horizontal motion
        match enemy_type.as_mut() {
            EnemyType::Horizontal(direction) => {
                velocity.linvel += *direction * vec2(30.0, 0.0);

                // direction update
                // 738 -> 1180 is the road x dir
                if transform.translation.x >= 1170.0 {
                    transform.translation.x = 1169.0;
                    *direction *= -1.0;
                } else if transform.translation.x <= 742.0 {
                    transform.translation.x = 743.0;
                    *direction *= -1.0;
                }
            }
            _ => {}
        }
    }
}

fn bound_control_system(mut query: Query<&mut Transform, With<BoundControlTruck>>) {
    for mut transform in query.iter_mut() {
        transform.translation.y += 1.0;
    }
}

pub fn spawn_enemies(commands: &mut Commands, asset_server: &AssetServer) {
    let mut enemy_y = 800.0;
    for _ in 0..NUM_ENEMY_CARS {
        let enemy_type = EnemyType::random();
        let enemy_scale = match enemy_type {
            EnemyType::Truck => 3.0,
            _ => 2.5,
        };
        let collider = match enemy_type {
            EnemyType::Truck => Collider::cuboid(6.0, 15.0),
            _ => Collider::cuboid(4.0, 8.0),
        };
        let mut rng = rand::thread_rng();
        let x = rng.gen_range(743.0..1169.0);
        let y = enemy_y;
        enemy_y += 200.0;
        commands.spawn((
            SpriteBundle {
                transform: Transform::from_xyz(x, y, 0.0).with_scale(vec3(
                    enemy_scale,
                    enemy_scale,
                    1.0,
                )),
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
            enemy_type,
        ));
    }
}

pub fn spawn_bound_trucks(commands: &mut Commands, asset_server: &AssetServer) {
    // Bound control trucks
    let enemy_y = 100.0;
    let mut enemy_x = 743.0; // upto 1169.0
    for _ in 0..12 {
        let enemy_type = EnemyType::Truck;
        let enemy_scale = 3.0;
        let collider = match enemy_type {
            EnemyType::Truck => Collider::cuboid(6.0, 15.0),
            _ => Collider::cuboid(4.0, 8.0),
        };
        let x = enemy_x;
        let y = enemy_y;

        enemy_x += 40.0;
        commands.spawn((
            SpriteBundle {
                transform: Transform::from_xyz(x, y, 0.0).with_scale(vec3(
                    enemy_scale,
                    enemy_scale,
                    1.0,
                )),
                texture: asset_server.load("bound-truck.png"),
                ..default()
            },
            RigidBody::Fixed,
            ActiveEvents::COLLISION_EVENTS,
            collider,
            Damping {
                angular_damping: 2.0,
                linear_damping: 2.0,
            },
            enemy_type,
            BoundControlTruck,
        ));
    }
}

impl EnemyType {
    fn random() -> Self {
        let all_vals = [Self::Horizontal(3.0), Self::Simple, Self::Truck];
        let mut rng = thread_rng();
        let index = rng.gen_range(0..all_vals.len());

        all_vals[index].clone()
    }

    fn get_sprite(&self) -> &str {
        let mut rng = thread_rng();
        match self {
            EnemyType::Simple => {
                let choices = ["enemy-blue-1.png", "enemy-yellow-1.png"];
                return choices[rng.gen_range(0..choices.len())];
            }
            EnemyType::Horizontal(_) => {
                let choices = [
                    "enemy-blue-2.png",
                    "enemy-yellow-2.png",
                    "enemy-yellow-3.png",
                ];
                return choices[rng.gen_range(0..choices.len())];
            }
            EnemyType::Truck => "enemy-truck.png",
        }
    }
}
