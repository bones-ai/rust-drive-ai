use std::f32::consts::PI;

use bevy::{log, math::vec3, prelude::*};
use bevy_prototype_debug_lines::DebugLinesPlugin;
use bevy_rapier2d::prelude::*;
// use rand::Rng;
use starknet::core::types::FieldElement;

use crate::dojo::SpawnRacersCommand;
use crate::nn::Net;
use crate::*;

pub struct CarPlugin;

#[derive(Component)]
pub struct Car {
    pub dojo_id: FieldElement,
}

#[derive(Component)]
pub struct Model {
    pub nn: Net,
    pub nn_outputs: Vec<Vec<f64>>,

    ray_inputs: Vec<f64>,
}

#[derive(Component, Reflect)]
struct TurnSpeed(f32);

#[derive(Component, Reflect)]
struct Steer(f32);

#[derive(Component, Reflect)]
struct Speed(f32);

#[derive(Component)]
pub struct Fitness(pub f32);

#[derive(Resource, Default)]
struct RayCastSensors(Vec<(f32, f32)>);

// wasd controls
struct CarControls(bool, bool, bool, bool);

#[derive(Bundle)]
pub struct CarBundle {
    sprite_bundle: SpriteBundle,
    car: Car,
    fitness: Fitness,
    model: Model,
    // speed: Speed,
    // velocity: Velocity,
    mass: ColliderMassProperties,
    rigid_body: RigidBody,
    collider: Collider,
    events: ActiveEvents,
    damping: Damping,
    sleep: Sleeping,
    ccd: Ccd,
    collision_groups: CollisionGroups,
}

impl Plugin for CarPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugin(DebugLinesPlugin::default())
            .add_event::<SpawnCars>()
            .register_type::<TurnSpeed>()
            .register_type::<Speed>()
            .insert_resource(RayCastSensors::default())
            .add_startup_system(setup)
            .add_system(spawn_cars);
        // .add_systems((car_render_system, spawn_cars));
        // .add_system(collision_events_system)
        // .add_system(sensors_system)
        // .add_system(car_nn_controlled_system.in_schedule(CoreSchedule::FixedUpdate));
    }
}

pub struct SpawnCars;

fn spawn_cars(mut events: EventReader<SpawnCars>, sender: Res<SpawnRacersCommand>) {
    for _ in events.iter() {
        if let Err(e) = sender.try_send() {
            log::error!("{e}");
        }
    }
}

// fn position_based_movement_system(controls: CarControls, transform: &mut Transform) {
//     let a_key = controls.1;
//     let d_key = controls.3;

//     let time_step = 1.0 / 60.0;
//     let mut rotation_factor = 0.0;

//     if a_key {
//         rotation_factor += 0.5;
//     } else if d_key {
//         rotation_factor -= 0.5;
//     }

//     transform.rotate_z(rotation_factor * 5.0 * time_step);
// }

fn setup(mut ray_cast_sensors: ResMut<RayCastSensors>) {
    // Pre compute the raycast directions
    let angle_per_ray = RAYCAST_SPREAD_ANGLE_DEG / (NUM_RAY_CASTS as f32) + 1.0;
    let mut current_angle = RAYCAST_START_ANGLE_DEG;
    for _ in 0..NUM_RAY_CASTS {
        let angle = current_angle * (PI / 180.0);
        let x = angle.cos();
        let y = angle.sin();
        ray_cast_sensors.0.push((x, y));

        current_angle += angle_per_ray;
    }
}

// fn collision_events_system(
//     mut commands: Commands,
//     mut collision_events: EventReader<CollisionEvent>,
// ) {
//     for collision_event in collision_events.iter() {
//         match collision_event {
//             CollisionEvent::Started(entity1, entity2, _) => {
//                 commands.entity(*entity2).remove::<Car>();
//                 commands.entity(*entity1).remove::<Car>();
//             }
//             _ => {}
//         }
//     }
// }

// fn car_render_system(mut car_query: Query<&mut Transform, With<Car>>) {
//     for mut transform in car_query.iter_mut() {
//         let movement_direction = transform.rotation * Vec3::Y;
//         let movement_distance = 3.5;
//         let translation_delta = movement_direction * movement_distance;
//         transform.translation += translation_delta;
//     }
// }

// fn car_nn_controlled_system(
//     mut car_query: Query<(&mut Speed, &mut Model, &mut Transform), With<Car>>,
// ) {
//     for (mut speed, mut model, mut transform) in car_query.iter_mut() {
//         if model.ray_inputs.is_empty() {
//             speed.0 = 0.0;
//             return;
//         }

//         model.nn_outputs = model.nn.predict(&model.ray_inputs);
//         let nn_out = model.nn_outputs[NUM_OUPUT_NODES - 1].clone();
//         //  nn_out = model.nn.predict(&model.ray_inputs).pop().unwrap();

//         // let w_key = nn_out[0] >= NN_W_ACTIVATION_THRESHOLD;
//         let w_key = false;
//         // let s_key = nn_out[2] >= NN_S_ACTIVATION_THRESHOLD;
//         let s_key = false;
//         let mut a_key = false;
//         let mut d_key = false;

//         if nn_out[0] >= 0.5 {
//             a_key = true;
//         } else {
//             d_key = true;
//         }

//         position_based_movement_system(CarControls(w_key, a_key, s_key, d_key), &mut transform);
//     }
// }

// fn draw_ray_cast(
//     lines: &mut DebugLines,
//     settings: &Settings,
//     start: Vec3,
//     end: Vec3,
//     color: Color,
// ) {
//     if !settings.is_show_rays {
//         return;
//     }

//     if start.y <= 700.0 && settings.is_hide_rays_at_start {
//         return;
//     }

//     lines.line_colored(start, end, 0.0, color);
// }

// fn sensors_system(
//     mut lines: ResMut<DebugLines>,
//     settings: Res<Settings>,
//     ray_cast_sensors: Res<RayCastSensors>,
//     rapier_context: Res<RapierContext>,
//     mut query: Query<(&Transform, &mut Model), With<Car>>,
// ) {
//     for (transform, mut model) in query.iter_mut() {
//         let raycast_filter = CollisionGroups {
//             memberships: Group::GROUP_1,
//             filters: Group::GROUP_2,
//         };
//         let filter = QueryFilter::default().groups(raycast_filter);
//         let ray_pos = transform.translation;
//         let mut nn_inputs = Vec::new();

//         // Ray casts
//         let rot = transform.rotation.z;
//         for (mut x, mut y) in ray_cast_sensors.0.iter() {
//             (x, y) = rotate_point(x, y, rot);
//             let dest_vec = vec2(x, y);
//             let end_point = calculate_endpoint(ray_pos, dest_vec, RAYCAST_MAX_TOI);
//             draw_ray_cast(&mut lines, &settings, ray_pos, end_point, Color::RED);

//             let ray_pos_2d = vec2(ray_pos.x, ray_pos.y);
//             if let Some((_, toi)) =
//                 rapier_context.cast_ray(ray_pos_2d, dest_vec, RAYCAST_MAX_TOI, false, filter)
//             {
//                 // The first collider hit has the entity `entity` and it hit after
//                 // the ray travelled a distance equal to `ray_dir * toi`.
//                 let hit_point = ray_pos_2d + dest_vec * toi;
//                 let hit_point = vec3(hit_point.x, hit_point.y, 0.0);

//                 // Invalidate when hit length more than max toi
//                 let dist_to_hit = ray_pos.distance(hit_point);
//                 nn_inputs.push(dist_to_hit as f64 / RAYCAST_MAX_TOI as f64);
//                 if dist_to_hit > RAYCAST_MAX_TOI {
//                     continue;
//                 }

//                 draw_ray_cast(&mut lines, &settings, ray_pos, hit_point, Color::GREEN);
//             } else {
//                 nn_inputs.push(1.0);
//             }
//         }

//         model.ray_inputs = nn_inputs;
//     }
// }

// fn calculate_endpoint(pos: Vec3, direction: Vec2, length: f32) -> Vec3 {
//     let dir = direction.normalize();
//     vec3(pos[0] + dir[0] * length, pos[1] + dir[1] * length, 0.0)
// }

// fn rotate_point(x: f32, y: f32, angle_rad: f32) -> (f32, f32) {
//     // Calculate the distance from the origin
//     let r = (x * x + y * y).sqrt();

//     // Calculate the current angle
//     let alpha = y.atan2(x);

//     // Add the rotation angle
//     let beta = alpha + angle_rad;

//     // Calculate the new coordinates
//     let x_prime = r * beta.cos();
//     let y_prime = r * beta.sin();

//     (x_prime, y_prime)
// }

impl CarBundle {
    pub fn new(asset_server: &AssetServer, dojo_id: FieldElement) -> Self {
        // let mut rng = rand::thread_rng();
        // let rand_x = rng.gen_range(800.0..1100.0);

        Self {
            sprite_bundle: SpriteBundle {
                transform: Transform::from_xyz(WINDOW_WIDTH / 2.00, WINDOW_HEIGHT / 2.0, 0.0)
                    .with_scale(vec3(2.5, 2.5, 1.0)),
                texture: asset_server.load("agent.png"),
                ..default()
            },
            car: Car { dojo_id },
            fitness: Fitness(0.0),
            model: Model {
                nn: Net::new(vec![
                    NUM_RAY_CASTS as usize,
                    NUM_HIDDEN_NODES,
                    NUM_OUPUT_NODES,
                ]),
                ray_inputs: Vec::new(),
                nn_outputs: Vec::new(),
            },
            // speed: Speed(0.0),
            // velocity: Velocity::zero(),
            mass: ColliderMassProperties::Mass(3000.0),
            rigid_body: RigidBody::Dynamic,
            collider: Collider::cuboid(5.0, 8.0),
            events: ActiveEvents::COLLISION_EVENTS,
            damping: Damping {
                angular_damping: 100.0,
                linear_damping: 100.0,
            },
            sleep: Sleeping::disabled(),
            ccd: Ccd::enabled(),
            collision_groups: CollisionGroups {
                memberships: Group::GROUP_1,
                filters: Group::GROUP_2,
            },
        }
    }

    pub fn with_model(asset_server: &AssetServer, model: &Net) -> Self {
        // TODO: generate dojo id
        let dojo_id = FieldElement::from_dec_str("0").unwrap();

        let mut car = CarBundle::new(asset_server, dojo_id);
        car.model.nn = model.clone();
        car
    }
}
