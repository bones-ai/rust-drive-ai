use traits::Into;
use cubit::types::vec2::{Vec2, Vec2Trait};
use cubit::types::fixed::{Fixed, FixedTrait, ONE_u128};
use cubit::math::{trig, comp::{min, max}, core::{pow_int, sqrt}};
use starknet::ContractAddress;
use drive_ai::{Vehicle, VehicleTrait};
use drive_ai::enemy::{
    Position, PositionTrait, ENEMIES_NB, GRID_HEIGHT, GRID_WIDTH, CAR_HEIGHT, CAR_WIDTH
};
use drive_ai::math;
use drive_ai::rays::{RaysTrait, Rays, Ray, RayTrait};
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

const RAY_LENGTH: u128 = 150;

fn compute_sensors(vehicle: Vehicle, mut enemies: Array<Position>) -> Sensors {
    let ray_segments = RaysTrait::new(vehicle.position, vehicle.steer).segments;

    // TODO: SCALE
    let filter_dist = FixedTrait::new_unscaled(CAR_WIDTH + RAY_LENGTH, false);

    let wall_sensors = match near_wall(vehicle) {
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
        if (ray_idx == 5) {
            break ();
        }

        enemy_sensors.append(closest_position(ray_segments.at(ray_idx), filtered_enemies.span()));

        ray_idx += 1;
    };

    // TODO: zip wall_sensors and enemy_sensors

    let mut shape = ArrayTrait::<usize>::new();
    shape.append(5);
    let mut sensors = ArrayTrait::<orion_fp::FixedType>::new();
    sensors.append(orion_fp::FixedTrait::new_unscaled(0, false));
    sensors.append(orion_fp::FixedTrait::new_unscaled(0, false));
    sensors.append(orion_fp::FixedTrait::new_unscaled(0, false));
    sensors.append(orion_fp::FixedTrait::new_unscaled(0, false));
    sensors.append(orion_fp::FixedTrait::new_unscaled(0, false));
    let extra = Option::<ExtraParams>::None(());
    Sensors { rays: TensorTrait::new(shape.span(), sensors.span(), extra) }
}

fn filter_positions(vehicle: Vehicle, mut positions: Array<Position>) -> Array<Position> {
    // For option 1 below
    // TODO: I think this assumes the orientation of the car? Might need to be a square with edges RAY + HEIGHT
    let max_horiz_dist = FixedTrait::new_unscaled(CAR_WIDTH + RAY_LENGTH, false);
    let max_vert_dist = FixedTrait::new_unscaled(CAR_HEIGHT + RAY_LENGTH, false);

    // // For option 2 below
    // let max_dist = FixedTrait::new_unscaled(CAR_HEIGHT + RAY_LENGTH, false);

    // Will hold near positions' enemy_idx values
    let mut near = ArrayTrait::new();

    loop {
        match positions.pop_front() {
            Option::Some(position) => {
                // Option 1: Box - This may be cheaper than distance calculation in option 2, 
                // but may include unneeded positions near corners of box, which could be more expensive
                // TODO: Avoid all the `FixedTrait::new_unscaled` calls
                if (FixedTrait::new_unscaled(position.x, false) - vehicle.position.x)
                    .abs() <= max_horiz_dist
                    && (FixedTrait::new_unscaled(position.y, false) - vehicle.position.y)
                        .abs() <= max_vert_dist {
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
    let mut closest = FixedTrait::new_unscaled(0, false);

    loop {
        match positions.pop_front() {
            Option::Some(position) => {
                let mut edge: usize = 0;

                // TODO: Only check visible edges
                loop {
                    if edge >= 3 {
                        break ();
                    }

                    let vertices = position.vertices();

                    // Endpoints of edge
                    let p2 = vertices.at(edge);
                    let mut q2_idx = edge + 1;
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

                    edge += 1;
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
    // TODO: SCALE
    if vehicle.position.x <= FixedTrait::new_unscaled(RAY_LENGTH, false) {
        return Wall::Left(());
    // TODO: SCALE
    } else if vehicle.position.x >= FixedTrait::new_unscaled(GRID_WIDTH - RAY_LENGTH, false) {
        return Wall::Right(());
    }
    return Wall::None(());
}

fn distances_to_wall(vehicle: Vehicle, near_wall: Wall, mut rays: Span<Ray>) -> Array<Fixed> {
    let mut sensors = ArrayTrait::<Fixed>::new();

    let ray_length = FixedTrait::new_unscaled(RAY_LENGTH, false);
    let car_height = FixedTrait::new_unscaled(CAR_HEIGHT, false);
    // TODO: Im not sure i understand this
    let half_wall_height = ray_length + car_height;

    let wall_position_x = match near_wall {
        Wall::None(()) => {
            return sensors;
        },
        Wall::Left(()) => FixedTrait::new(0, false),
        // TODO: SCALE
        Wall::Right(()) => FixedTrait::new_unscaled(GRID_WIDTH, false),
    };

    let p2 = Vec2 { x: wall_position_x, y: vehicle.position.y - half_wall_height };
    let q2 = Vec2 { x: wall_position_x, y: vehicle.position.y + half_wall_height };

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

// TODO
fn collision_enemy_check() {}

// TODO
fn collision_wall_check() {}


#[system]
mod spawn_racer {
    use array::ArrayTrait;
    use traits::Into;
    use cubit::types::FixedTrait;
    use cubit::types::Vec2Trait;

    use dojo::world::Context;
    use drive_ai::Vehicle;

    use super::Racer;

    fn execute(ctx: Context, model: felt252) {
        let position = Vec2Trait::new(
            FixedTrait::new_unscaled(50, false), FixedTrait::new_unscaled(0, false)
        );
        set !(
            ctx.world,
            model.into(),
            (
                Racer {
                    driver: ctx.origin, model
                    }, Vehicle {
                    position,
                    steer: FixedTrait::new_unscaled(0_u128, false),
                    speed: FixedTrait::new_unscaled(50_u128, false),
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
        let mut controls = ctx.world.execute(model, sensor_calldata.span());
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

    use super::{Sensors, near_wall};

    const TEN: felt252 = 184467440737095516160;
    const HUNDRED: felt252 = 1844674407370955161600;

    // TODO FINISH
    #[test]
    #[available_gas(20000000)]
    fn test_sensors() {}

    #[test]
    #[available_gas(20000000)]
    fn test_near_obstacles() {}

    #[test]
    #[available_gas(20000000)]
    fn test_near_enemies() {
        let vehicle = Vehicle {
            position: Vec2Trait::new(FixedTrait::from_felt(HUNDRED), FixedTrait::from_felt(TEN)),
            steer: FixedTrait::new(0, false),
            speed: FixedTrait::new(0, false)
        };
        let mut enemies = ArrayTrait::<Vehicle>::new();
        let mut enemy = Vehicle {
            position: Vec2Trait::new(FixedTrait::from_felt(HUNDRED), FixedTrait::from_felt(TEN)),
            steer: FixedTrait::new(0, false),
            speed: FixedTrait::new(10, false)
        };
    }

    // TODO
    #[test]
    #[available_gas(20000000)]
    fn test_near_wall() {}

    // TODO
    #[test]
    #[available_gas(20000000)]
    fn test_distances_to_enemy() {}

    // TODO
    #[test]
    #[available_gas(20000000)]
    fn test_distances_to_wall() {}

    // TODO
    #[test]
    #[available_gas(20000000)]
    fn test_collision_enemy_check() {}

    // TODO
    #[test]
    #[available_gas(20000000)]
    fn test_collision_wall_check() {}
}
