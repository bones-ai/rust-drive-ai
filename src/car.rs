use std::f32::consts::PI;

use bevy::{
    math::{vec2, vec3},
    prelude::*,
};
use bevy_rapier2d::prelude::*;
use rand::Rng;

use crate::*;
use crate::nn::Net;

pub struct CarPlugin;

#[derive(Component)]
pub struct Car;

#[derive(Component,Clone)]
pub struct Brain {
    pub nn: Net,
    pub nn_outputs: Vec<Vec<f64>>,
    ray_inputs: Vec<f64>,
}

#[derive(Component, Reflect)]
struct TurnSpeed(f32);

#[derive(Component, Reflect)]
struct Speed(f32);

#[derive(Component)]
pub struct Fitness(pub f32);

#[derive(Resource, Default)]
struct RayCastSensors(Vec<(f32, f32)>);

// wasd controls
#[derive(Copy, Clone)]
struct CarControls {
    w: bool,
    a: bool,
    s: bool,
    d: bool,
}

#[derive(Bundle)]
pub struct CarBundle {
    sprite_bundle: SpriteBundle,
    car: Car,
    fitness: Fitness,
    brain: Brain,
    turn_speed: TurnSpeed,
    speed: Speed,
    velocity: Velocity,
    mass: ColliderMassProperties,
    rigid_body: RigidBody,
    collider: Collider,
    events: ActiveEvents,
    damping: Damping,
    sleep: Sleeping,
    ccd: Ccd,
    collision_groups: CollisionGroups,
}

#[derive(Resource)]
pub struct NNSave {
    pub should_save: bool,
    pub already_loaded: bool,
}

impl Default for NNSave {
    fn default() -> Self {
        Self {
            should_save: true,
            already_loaded: false,
        }
    }
}

impl Plugin for CarPlugin {
    fn build(&self, app: &mut App) {
        app
            .register_type::<TurnSpeed>()
            .register_type::<Speed>()
            .insert_resource(RayCastSensors::default())
            .insert_resource(NNSave::default())
            .add_systems(Startup, setup)
            // .add_system(car_manual_input_system)
            .add_systems(Update, car_nn_controlled_system)
            // .add_system(car_gas_system)
            // .add_system(car_steer_system)
            .add_systems(Update, collision_events_system)
            .add_systems(Update, sensors_system);
    }
}

fn position_based_movement_system(
    controls: CarControls,
    transform: &mut Transform,
    delta_sec: f32,
) {
    let w_key = controls.w;
    let a_key = controls.a;
    let s_key = controls.s;
    let d_key = controls.d;

    let time_step = delta_sec; //1.0 / 60.0;
    let mut rotation_factor = 0.0;
    let mut movement_factor = 0.0;

    if w_key {
        movement_factor += 3.5;
    }
    if a_key {
        rotation_factor += 0.5;
    } else if d_key {
        rotation_factor -= 0.5;
    }

    transform.rotate_z(rotation_factor * 5.0 * time_step);
    let movement_direction = transform.up(); //transform.rotation * Vec3::Y;
    let movement_distance = movement_factor;
    let translation_delta = movement_direction * movement_distance;
    transform.translation += translation_delta;
}

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

fn collision_events_system(
    mut commands: Commands,
    mut collision_events: EventReader<CollisionEvent>,
) {
    for collision_event in collision_events.iter() {
        match collision_event {
            CollisionEvent::Started(entity1, entity2, _) => {
                commands.entity(*entity2).remove::<Car>();
                commands.entity(*entity1).remove::<Car>();
            }
            _ => {}
        }
    }
}

fn car_nn_controlled_system(
    time: Res<Time>,
    mut car_query: Query<(&mut Speed, &mut TurnSpeed, &mut Brain, &mut Transform), With<Car>>,
) {
    for (mut speed, mut turn_speed, mut brain, mut transform) in car_query.iter_mut() {
        if brain.ray_inputs.is_empty() {
            speed.0 = 0.0;
            turn_speed.0 = 0.0;
            return;
        }

        brain.nn_outputs = brain.nn.predict(&brain.ray_inputs);
        let nn_out = brain.nn_outputs[NUM_OUPUT_NODES - 1].clone();
        //  nn_out = brain.nn.predict(&brain.ray_inputs).pop().unwrap();

        // let w_key = nn_out[0] >= NN_W_ACTIVATION_THRESHOLD;
        let mut w_key = true;
        // let s_key = nn_out[2] >= NN_S_ACTIVATION_THRESHOLD;
        let mut s_key = false;
        let mut a_key = false;
        let mut d_key = false;

        if nn_out[1] >= 0.5 {
            a_key = true;
        } else {
            d_key = true;
        }
        if nn_out[2] >= 0.9 {
            s_key = true;
        } else {
            w_key = true;
        }

        // update_car_input(
        //     CarControls(w_key, a_key, s_key, d_key),
        //     &mut turn_speed,
        //     &mut speed,
        //     &time,
        // );
        let time_delta = time.delta_seconds();
        let controls = CarControls{w: w_key, a: a_key, s: s_key, d: d_key};
        position_based_movement_system(controls, &mut transform, time_delta);
    }
}

#[allow(dead_code)]
fn car_manual_input_system(
    time: Res<Time>,
    keyboard_input: Res<Input<KeyCode>>,
    mut car_query: Query<(&mut Speed, &mut TurnSpeed, &mut Transform), With<Car>>,
) {
    for (mut speed, mut turn_speed, mut transform) in car_query.iter_mut() {
        let w_key = keyboard_input.pressed(KeyCode::W);
        let a_key = keyboard_input.pressed(KeyCode::A);
        let s_key = keyboard_input.pressed(KeyCode::S);
        let d_key = keyboard_input.pressed(KeyCode::D);
        let controls = CarControls {
                w: w_key, a: a_key, s: s_key, d: d_key,
            };

        let time_delta = time.delta_seconds();
        update_car_input(
            controls,
            &mut turn_speed,
            &mut speed,
            time_delta,
        );
        position_based_movement_system(controls, &mut transform, time_delta);
    }
}

fn update_car_input(
    controls: CarControls,
    turn_speed: &mut TurnSpeed,
    speed: &mut Speed,
    time_delta: f32,
) {
    let w_key = controls.w;
    let a_key = controls.a;
    let s_key = controls.s;
    let d_key = controls.d;

    turn_speed.0 = if a_key {
        TURN_SPEED
    } else if d_key {
        -TURN_SPEED
    } else {
        0.0
    };

    // Friction code from: https://github.com/Rust-Ninja-Sabi/bevyastro
    speed.0 = if s_key {
        if speed.0.abs() <= 30.0 {
            0.0
        } else {
            speed.0 - FRICTION * time_delta * 1.2
        }
    } else if w_key {
        speed.0 + CAR_THRUST * time_delta
    } else {
        if speed.0.abs() <= 30.0 {
            // Avoid speed from over shooting
            // and be non zero all the time
            0.0
        } else if speed.0 > 0.0 {
            speed.0 - FRICTION * time_delta
        } else if speed.0 < 0.0 {
            speed.0 + FRICTION * time_delta
        } else {
            0.0
        }
    };

    speed.0 = speed.0.clamp(-MAX_SPEED + MAX_SPEED / 2.0, MAX_SPEED);
}

fn car_gas_system(
    time: Res<Time>,
    mut query: Query<(&Transform, &Speed, &mut Velocity), With<Car>>,
) {
    for (transform, speed, mut velocity) in query.iter_mut() {
        let y_dir = transform.local_y();
        if speed.0 == 0.0 {
            let direction = y_dir;
            velocity.linvel = direction.truncate() * 0.0000001;
            return;
        }

        let translation_delta = y_dir * speed.0;
        velocity.linvel =
            translation_delta.truncate() * 25.0 * time.delta_seconds();
    }
}

fn car_steer_system(
    time: Res<Time>,
    mut query: Query<(&Speed, &TurnSpeed, &mut Velocity), With<Car>>,
) {
    for (speed, turn_speed, mut velocity) in query.iter_mut() {
        if speed.0.abs() < MIN_SPEED_TO_STEER {
            velocity.angvel = 0.0;
            return;
        }

        velocity.angvel = turn_speed.0 * time.delta_seconds() * TURN_SPEED;
    }
}

fn draw_ray_cast(
    settings: &Settings,
    start: Vec2,
    end: Vec2,
    color: Color,
    gizmos: &mut Gizmos,
) {
    if !settings.is_show_rays {
        return;
    }
    if start.y <= 2000.0 && settings.is_hide_rays_at_start {
        return;
    }
    gizmos.line_2d(start, end, color);
}

fn sensors_system(
    settings: Res<Settings>,
    ray_cast_sensors: Res<RayCastSensors>,
    rapier_context: Res<RapierContext>,
    mut gizmos: Gizmos,
    mut query: Query<(&Transform, &Velocity, &mut Brain, &Speed, &TurnSpeed), With<Car>>,
) {
    let raycast_filter = CollisionGroups {
        memberships: Group::GROUP_1,
        filters: Group::GROUP_2,
    };
    let filter = QueryFilter::default().groups(raycast_filter);
    for (transform, velocity, mut brain, speed, turn_speed) in query.iter_mut() {
        let ray_pos = transform.translation;
        let ray_pos_2d = ray_pos.xy();
        let mut nn_inputs = Vec::new();

        // Ray casts
        // let rot = velocity.linvel.y.atan2(velocity.linvel.x) - PI / 2.0;
        // let rot = transform.rotation.z;
        // let rot = turn_speed.0;
        for (idx, (x, y)) in ray_cast_sensors.0.iter().enumerate() {
            let ray_len = match idx % 3 {
                0 => RAYCAST_MAX_TOI,
                1 => RAYCAST_MAX_TOI / 2.0,
                _ => RAYCAST_MAX_TOI / 3.0,
            };
            // let ray_len = if idx & 0b1 == 0 { RAYCAST_MAX_TOI } else { RAYCAST_MAX_TOI / 2f32 };

            let ray_dir_2d = (transform.rotation * vec2(*x,*y).extend(0.0)).truncate().normalize();//.truncate();
            // let (x_r, y_r) = rotate_point(*x, *y, rot);
            // let ray_dir_2d = vec2(x_r, y_r).normalize();

            let ray_end_point_2d = ray_pos_2d + ray_dir_2d * ray_len;
            let nn_input =
                if let Some((_, toi)) =
                    rapier_context.cast_ray(ray_pos_2d, ray_dir_2d, ray_len, false, filter)
                {
                    // The first collider hit has the entity `entity` and it hit after
                    // the ray travelled a distance equal to `ray_dir * toi`.
                    // let dist_to_hit = ray_dir_2d * toi;
                    let dist_to_hit = toi;
                    // let hit_point_2d = ray_pos_2d + ray_dir_2d * toi;

                    // Invalidate when hit length more than max toi
                    // let dist_to_hit = ray_pos_2d.distance(hit_point_2d);
                    let ai_value = dist_to_hit as f64 / ray_len as f64 * 0.75f64; // to differentiate a hit v.s. a non-hit
                    let ray_color =
                        if dist_to_hit > RAYCAST_MAX_TOI {
                            Color::RED
                        } else {
                            Color::GREEN
                        };
                    draw_ray_cast(&settings, ray_pos_2d, ray_end_point_2d, ray_color, &mut gizmos);
                    ai_value
                } else {
                    draw_ray_cast(&settings, ray_pos_2d, ray_end_point_2d, Color::RED, &mut gizmos);
                    1.0
                };
            nn_inputs.push(nn_input);
        }
        brain.ray_inputs = nn_inputs;
    }
}

fn rotate_point(x: f32, y: f32, angle_rad: f32) -> (f32, f32) {
    // Calculate the distance from the origin
    let r = (x * x + y * y).sqrt();

    // Calculate the current angle
    let alpha = y.atan2(x);

    // Add the rotation angle
    let beta = alpha + angle_rad;

    // Calculate the new coordinates
    let x_prime = r * beta.cos();
    let y_prime = r * beta.sin();

    (x_prime, y_prime)
}

impl CarBundle {
    fn create_bundle() -> Vec<usize> {
        vec![
            NUM_RAY_CASTS as usize,
            NUM_HIDDEN_NODES,
            NUM_HIDDEN_NODES_2,
            NUM_OUPUT_NODES,
        ]
    }

    pub fn with_brain(asset_server: &AssetServer, nn: Net) -> Self {
        let mut rng = rand::thread_rng();
        let rand_x = rng.gen_range(800.0..1100.0);

        Self {
            sprite_bundle: SpriteBundle {
                transform: Transform::from_xyz(rand_x, WINDOW_HEIGHT / 2.0, 0.0)
                    .with_scale(vec3(2.5, 2.5, 1.0)),
                texture: asset_server.load("agent.png"),
                ..default()
            },
            car: Car,
            fitness: Fitness(0.0),
            brain: Brain {
                nn,
                ray_inputs: Vec::new(),
                nn_outputs: Vec::new(),
            },
            turn_speed: TurnSpeed(0.0),
            speed: Speed(0.0),
            velocity: Velocity::zero(),
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

    pub fn load_brain() -> Result<Net,Net> {
        let nn_items = Self::create_bundle();
        let sample = Net::new(&nn_items);
        Net::load_net(&sample, &nn_items, NN_SAVE_FILE)
    }

    pub fn new(asset_server: &AssetServer) -> Self {
        let nn = Net::new(&Self::create_bundle());
        Self::with_brain(asset_server, nn)
    }
}

