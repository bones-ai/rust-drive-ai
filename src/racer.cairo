use traits::Into;
use cubit::types::vec2::{Vec2, Vec2Trait};
use cubit::types::fixed::{Fixed, FixedTrait, ONE_u128};
use cubit::math::{trig, comp::{min, max}, core::{pow_int, sqrt}};
use starknet::ContractAddress;
use drive_ai::{Vehicle, VehicleTrait};
use drive_ai::enemy::{Position, PositionTrait};
use drive_ai::math::{intersects};
use drive_ai::rays::{RaysTrait, Rays, Ray, RayTrait, NUM_RAYS, RAY_LENGTH};
use array::{ArrayTrait, SpanTrait};

use orion::operators::tensor::core::{Tensor, TensorTrait, ExtraParams};
use orion::numbers::fixed_point::core as orion_fp;
use orion::numbers::fixed_point::implementations::impl_16x16::FP16x16Impl;
use orion::operators::tensor::implementations::impl_tensor_fp::Tensor_fp;

#[derive(Component, Serde, SerdeLen, Drop, Copy)]
struct Racer {
    // Vehicle owner
    driver: ContractAddress,
    // Model system name
    model: felt252,
}

#[derive(Serde, Drop)]
struct Sensors {
    rays: Tensor<orion_fp::FixedType>, 
}

#[derive(Serde, Drop, PartialEq)]
enum Wall {
    None: (),
    Left: (),
    Right: (),
}

const GRID_HEIGHT: u128 = 18446744073709551616000; // 1000
const GRID_WIDTH: u128 = 7378697629483820646400; // 400
const HALF_GRID_WIDTH: u128 = 3689348814741910323200; // 200
const CAR_HEIGHT: u128 = 590295810358705651712; // 32
const CAR_WIDTH: u128 = 295147905179352825856; // 16

fn compute_sensors(vehicle: Vehicle, mut enemies: Array<Position>) -> Sensors {
    let ray_segments = RaysTrait::new(vehicle.position, vehicle.steer).segments;

    let filter_dist = FixedTrait::new(CAR_WIDTH + RAY_LENGTH, false); // Is this used?

    let mut wall_sensors = match near_wall(vehicle) {
        Wall::None(()) => {
            ArrayTrait::<Fixed>::new()
        },
        Wall::Left(()) => {
            distances_to_wall(vehicle, Wall::Left(()), ray_segments)
        },
        Wall::Right(()) => {
            distances_to_wall(vehicle, Wall::Right(()), ray_segments)
        },
    };

    let filtered_enemies = filter_positions(vehicle, enemies);

    // Iterate over all enemeies for each sensor and find the closest one
    let mut enemy_sensors = ArrayTrait::<Fixed>::new();
    let mut ray_idx = 0;
    loop {
        if (ray_idx == NUM_RAYS) {
            break ();
        }

        enemy_sensors.append(closest_position(ray_segments.at(ray_idx), filtered_enemies.span()));

        ray_idx += 1;
    };

    let mut sensors = ArrayTrait::<orion_fp::FixedType>::new();

    let mut idx = 0;
    if wall_sensors.len() > 0 {
        loop {
            if idx == NUM_RAYS {
                break ();
            }

            let wall_sensor = *wall_sensors.at(idx);
            let enemy_sensor = *enemy_sensors.at(idx);

            if wall_sensor < enemy_sensor {
                sensors.append(orion_fp::FixedTrait::new(wall_sensor.mag, false));
            } else {
                sensors.append(orion_fp::FixedTrait::new(enemy_sensor.mag, false));
            };

            idx += 1;
        }
    } else {
        loop {
            if idx == NUM_RAYS {
                break ();
            }

            sensors.append(orion_fp::FixedTrait::new(*enemy_sensors.at(idx).mag, false));

            idx += 1;
        }
    }

    let mut shape = ArrayTrait::<usize>::new();
    shape.append(5);
    let extra = Option::<ExtraParams>::None(());
    Sensors { rays: TensorTrait::new(shape.span(), sensors.span(), extra) }
}

fn filter_positions(vehicle: Vehicle, mut positions: Array<Position>) -> Array<Position> {
    // Will hold near position values
    let mut near = ArrayTrait::new();

    let max_dist = FixedTrait::new(CAR_HEIGHT + RAY_LENGTH, false);

    loop {
        match positions.pop_front() {
            Option::Some(position) => {
                // Option 1: Box - This may be cheaper than distance calculation in option 2, 
                // but may include unneeded positions near corners of box, which could be more expensive
                if (FixedTrait::new(position.x, false) - vehicle.position.x).abs() <= max_dist
                    && (FixedTrait::new(position.y, false) - vehicle.position.y).abs() <= max_dist {
                    near.append(position);
                }
            // // Option 2: Semi-circle - This may eliminate some positions near corners of box in option 2,
            // // but may include (probably fewer) unneeded positions at the sides where max distance reduces 
            // // to as low as CAR_WIDTH + RAY_LENGTH
            // let delta_x_squared = pow_int(position.x - vehicle.position.x, 2, false);
            // let delta_y_squared = pow_int(position.y - vehicle.position.y, 2, false);
            // let distance = sqrt(delta_x_squared + delta_y_squared);
            // if distance <= max_dist {
            //     near.append(enemy_idx);
            // }
            },
            Option::None(_) => {
                break ();
            }
        };
    };

    near
}

fn closest_position(ray: @Ray, mut positions: Span<Position>) -> Fixed {
    let mut closest = FixedTrait::new(0, false); // Should this be non-zero?

    loop {
        match positions.pop_front() {
            Option::Some(position) => {
                let mut edge_idx: usize = 0;

                let vertices = position.vertices();

                // TODO: Only check visible edges
                loop {
                    if edge_idx == 3 {
                        break ();
                    }

                    // Endpoints of edge
                    let p2 = vertices.at(edge_idx);
                    let mut q2_idx = edge_idx + 1;
                    if q2_idx == 4 {
                        q2_idx = 0;
                    }

                    let q2 = vertices.at(q2_idx);
                    if ray.intersects(*p2, *q2) {
                        let dist = ray.dist(*p2, *q2);
                        if dist < closest {
                            closest = dist;
                        }
                    }

                    edge_idx += 1;
                }
            },
            Option::None(_) => {
                break ();
            }
        };
    };

    closest
}

fn near_wall(vehicle: Vehicle) -> Wall {
    if vehicle.position.x <= FixedTrait::new(RAY_LENGTH, false) {
        return Wall::Left(());
    } else if vehicle.position.x >= FixedTrait::new(GRID_WIDTH - RAY_LENGTH, false) {
        return Wall::Right(());
    }
    return Wall::None(());
}

fn distances_to_wall(vehicle: Vehicle, near_wall: Wall, mut rays: Span<Ray>) -> Array<Fixed> {
    let mut sensors = ArrayTrait::<Fixed>::new();

    let ray_length = FixedTrait::new(RAY_LENGTH, false);

    let wall_position_x = match near_wall {
        Wall::None(()) => {
            return sensors;
        },
        Wall::Left(()) => FixedTrait::new(0, false),
        Wall::Right(()) => FixedTrait::new(GRID_WIDTH, false),
    };

    let p2 = Vec2 { x: wall_position_x, y: FixedTrait::new(0, false) };
    let q2 = Vec2 { x: wall_position_x, y: FixedTrait::new(GRID_HEIGHT, false) };

    // TODO: We can exit early on some conditions here, since, for example, if the left most ray math::intersects, the right most can't
    loop {
        match rays.pop_front() {
            Option::Some(ray) => {
                // Endpoints of Ray
                if ray.intersects(p2, q2) {
                    sensors.append(ray.dist(p2, q2));
                } else {
                    sensors.append(FixedTrait::new(0, false));
                }
            },
            Option::None(_) => {
                break ();
            }
        };
    };

    sensors
}

fn collision_check(vehicle: Vehicle, mut enemies: Array<Position>) {
    let vertices = vehicle.vertices();

    /// Wall collision check
    match near_wall(vehicle) {
        Wall::None(()) => {},
        Wall::Left(()) => { // not 100% sure of syntax here at end
            let cos_theta = trig::cos_fast(vehicle.steer);
            let sin_theta = trig::sin_fast(vehicle.steer);

            // Check only left edge (vertex 1 to 2)
            let closest_edge = Ray {
                theta: vehicle.steer,
                cos_theta: cos_theta,
                sin_theta: sin_theta,
                p: *vertices.at(1),
                q: *vertices.at(2),
            };
            let p2 = Vec2 { x: FixedTrait::new(0, false), y: FixedTrait::new(0, false) };
            let q2 = Vec2 { x: FixedTrait::new(0, false), y: FixedTrait::new(GRID_HEIGHT, false) };

            assert(!closest_edge.intersects(p2, q2), 'hit left wall');
        },
        Wall::Right(()) => { // not 100% sure of syntax here at end
            let cos_theta = trig::cos_fast(vehicle.steer);
            let sin_theta = trig::sin_fast(vehicle.steer);

            // Check only right edge (vertex 3 to 0)
            let closest_edge = Ray {
                theta: vehicle.steer,
                cos_theta: cos_theta,
                sin_theta: sin_theta,
                p: *vertices.at(3),
                q: *vertices.at(0),
            };

            let p2 = Vec2 { x: FixedTrait::new(GRID_WIDTH, false), y: FixedTrait::new(0, false) };
            let q2 = Vec2 {
                x: FixedTrait::new(GRID_WIDTH, false), y: FixedTrait::new(GRID_HEIGHT, false)
            };

            assert(!closest_edge.intersects(p2, q2), 'hit right wall');
        },
    };

    /// Enemy collision check
    // Get array of only near enemies positions
    let mut filtered_enemies = filter_positions(vehicle, enemies);

    // For each vehicle edge...
    let mut vehicle_edge_idx: usize = 0;
    loop {
        if (vehicle_edge_idx == 3) {
            break ();
        }

        let mut q1_idx = vehicle_edge_idx + 1;
        if q1_idx == 4 {
            q1_idx = 0;
        }
        // Endpoints of vehicle edge
        let p1 = vertices.at(vehicle_edge_idx);
        let q1 = vertices.at(q1_idx);

        // ..., check for collision with each near enemy
        loop {
            match filtered_enemies.pop_front() {
                Option::Some(position) => {
                    let mut enemy_edge_idx: usize = 0;

                    let vertices = position.vertices();

                    // For each enemy edge
                    // TODO: Only check visible edges
                    loop {
                        if enemy_edge_idx == 3 {
                            break ();
                        }

                        let mut q2_idx = enemy_edge_idx + 1;
                        if q2_idx == 4 {
                            q2_idx = 0;
                        }

                        // Endpoints of enemy edge
                        let p2 = vertices.at(enemy_edge_idx);
                        let q2 = vertices.at(q2_idx);

                        assert(!intersects(*p1, *q1, *p2, *q2), 'hit enemy');

                        enemy_edge_idx += 1;
                    }
                },
                Option::None(_) => {
                    break ();
                }
            };
        };
        vehicle_edge_idx += 1;
    };
}


#[system]
mod spawn_racer {
    use array::ArrayTrait;
    use traits::Into;
    use cubit::types::FixedTrait;
    use cubit::types::Vec2Trait;

    use dojo::world::Context;
    use drive_ai::Vehicle;

    use super::{Racer, HALF_GRID_WIDTH};

    const FIFTY: u128 = 922337203685477580800;

    fn execute(ctx: Context, model: felt252) {
        let position = Vec2Trait::new(
            FixedTrait::new(HALF_GRID_WIDTH, false), FixedTrait::new(0, false)
        );
        set !(
            ctx.world,
            model.into(),
            (
                Racer {
                    driver: ctx.origin, model
                    }, Vehicle {
                    position,
                    steer: FixedTrait::new(0_u128, false),
                    speed: FixedTrait::new(FIFTY, false),
                }
            )
        );

        let mut calldata = ArrayTrait::new();
        calldata.append(model);
        ctx.world.execute('spawn_enemies', calldata.span());

        return ();
    }
}

#[system]
mod drive {
    use array::ArrayTrait;
    use traits::Into;
    use serde::Serde;
    use dojo::world::Context;
    use drive_ai::vehicle::{Controls, Vehicle, VehicleTrait};
    use drive_ai::enemy::{Position, ENEMIES_NB};
    use super::{Racer, Sensors, compute_sensors};

    fn execute(ctx: Context, model: felt252) {
        let mut vehicle = get !(ctx.world, model.into(), Vehicle);

        let mut enemies = ArrayTrait::<Position>::new();
        let mut i: u8 = 0;
        loop {
            if i == ENEMIES_NB {
                break ();
            }
            let key = (model, i).into();
            let position = get !(ctx.world, key, Position);
            enemies.append(position);
            i += 1;
        }

        // 1. Compute sensors, reverts if there is a collision (game over)
        let sensors = compute_sensors(vehicle, enemies);
        // 2. Run model forward pass
        let mut sensor_calldata = ArrayTrait::new();
        sensors.serialize(ref sensor_calldata);
        let mut controls = ctx.world.execute('model', sensor_calldata.span());
        let controls = serde::Serde::<Controls>::deserialize(ref controls).unwrap();
        // 3. Update car position
        vehicle.control(controls);
        vehicle.drive();
        set !(
            ctx.world,
            model.into(),
            (Vehicle { position: vehicle.position, steer: vehicle.steer, speed: vehicle.speed })
        );

        // 4. Move enemeies to updated positions
        // TODO: This retrieves enemies again internally, we should
        // only read them once (pass them in here?)
        let mut calldata = ArrayTrait::new();
        calldata.append(model);
        ctx.world.execute('move_enemies', calldata.span());
    }
}

#[cfg(test)]
mod tests {
    use debug::PrintTrait;
    use cubit::types::vec2::{Vec2, Vec2Trait};
    use cubit::types::fixed::{Fixed, FixedTrait, FixedPrint, ONE_u128};
    use cubit::math::trig;
    use cubit::test::helpers::assert_precise;
    use array::SpanTrait;
    use drive_ai::{Vehicle, VehicleTrait};
    use drive_ai::rays::{RAY_LENGTH};
    use super::{
        compute_sensors, filter_positions, closest_position, near_wall, distances_to_wall,
        collision_check, Wall
    };
    use super::{CAR_WIDTH, GRID_WIDTH};

    const TWO: u128 = 36893488147419103232;
    const TEN: u128 = 184467440737095516160;
    const HUNDRED: u128 = 1844674407370955161600;

    #[test]
    #[available_gas(20000000)]
    fn test_compute_sensors() {
        let vehicle = Vehicle {
            position: Vec2Trait::new(
                FixedTrait::new(CAR_WIDTH, false), FixedTrait::new(TEN, false)
            ),
            steer: FixedTrait::new(0, false),
            speed: FixedTrait::new(0, false)
        };
    }

    // TODO
    #[test]
    #[available_gas(20000000)]
    fn test_filter_positions() {}

    // TODO
    #[test]
    #[available_gas(20000000)]
    fn test_closest_position() {}

    #[test]
    #[available_gas(20000000)]
    fn test_near_wall() {
        let vehicle_near_left_wall = Vehicle {
            position: Vec2Trait::new(
                FixedTrait::new(CAR_WIDTH, false), FixedTrait::new(TEN, false)
            ),
            steer: FixedTrait::new(0, false),
            speed: FixedTrait::new(0, false)
        };
        let left_wall = near_wall(vehicle_near_left_wall);
        assert(left_wall == Wall::Left(()), 'invalid near left wall');

        let vehicle_near_no_wall = Vehicle {
            position: Vec2Trait::new(
                FixedTrait::new(GRID_WIDTH, false) / FixedTrait::new(TWO, false),
                FixedTrait::new(TEN, false)
            ),
            steer: FixedTrait::new(0, false),
            speed: FixedTrait::new(0, false)
        };
        let no_wall = near_wall(vehicle_near_no_wall);
        assert(no_wall == Wall::None(()), 'invalid near no wall');

        let vehicle_near_right_wall = Vehicle {
            position: Vec2Trait::new(
                FixedTrait::new(GRID_WIDTH - CAR_WIDTH, false), FixedTrait::new(TEN, false)
            ),
            steer: FixedTrait::new(0, false),
            speed: FixedTrait::new(0, false)
        };
        let right_wall = near_wall(vehicle_near_right_wall);
        assert(right_wall == Wall::Right(()), 'invalid near right wall');
    }

    // TODO
    #[test]
    #[available_gas(20000000)]
    fn test_distances_to_wall() {}

    // TODO
    #[test]
    #[available_gas(20000000)]
    fn test_collision_check() {}
}
