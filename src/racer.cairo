use cubit::types::vec2::{Vec2, Vec2Trait};
use cubit::types::fixed::{Fixed, FixedTrait, ONE_u128};
use cubit::math::{trig, comp};
use starknet::ContractAddress;
use drive_ai::{Vehicle, VehicleTrait};
use array::{ArrayTrait, SpanTrait};

#[derive(Component, Serde, SerdeLen, Drop, Copy)]
struct Racer {
    // Vehicle owner
    driver: ContractAddress,
    // Model system name
    model: felt252,
}

#[derive(Serde, Drop)]
struct Sensors {
    distances_to_obstacle: Array<Fixed>, 
}

const NUM_RAYS: u128 = 9; // must be ODD integer
const RAYS_TOTAL_ANGLE_DEG: u128 = 140;
const RAY_LENGTH: u128 = 150;

const DEG_90_IN_RADS: felt252 = 28976077338029890953;
const DEG_70_IN_RADS: felt252 = 22536387234850959209;
const DEG_50_IN_RADS: felt252 = 16098473553126325695;
const DEG_30_IN_RADS: felt252 = 9658715196994321226;
const DEG_10_IN_RADS: felt252 = 3218956840862316756;

fn distances_to_enemy(vehicle: Vehicle, enemy: Vehicle) -> Array<Fixed> {
    // Empties then fills Sensors mutable array self.distances_to_obstacle for particular Enemy
    let mut distances_to_obstacle = ArrayTrait::new();

    let ray_length = FixedTrait::new(RAY_LENGTH, false);
    let enemy_vertices = enemy.vertices();

    let mut rays = ArrayTrait::new();
    // rays.append(vehicle.steer - FixedTrait::from_felt(-1 * DEG_70_IN_RADS));
    // rays.append(vehicle.steer - FixedTrait::from_felt(-1 * DEG_50_IN_RADS));
    // rays.append(vehicle.steer - FixedTrait::from_felt(-1 * DEG_30_IN_RADS));
    // rays.append(vehicle.steer - FixedTrait::from_felt(-1 * DEG_10_IN_RADS));
    rays.append(vehicle.steer);
    // rays.append(vehicle.steer - FixedTrait::from_felt(DEG_10_IN_RADS));
    // rays.append(vehicle.steer - FixedTrait::from_felt(DEG_30_IN_RADS));
    // rays.append(vehicle.steer - FixedTrait::from_felt(DEG_50_IN_RADS));
    // rays.append(vehicle.steer - FixedTrait::from_felt(DEG_70_IN_RADS));

    loop {
        match rays.pop_front() {
            Option::Some(ray) => {
                // Endpoints of Ray
                let p1 = vehicle.position;
                let cos_ray = trig::cos(ray);
                let sin_ray = trig::sin(ray);
                let delta1 = Vec2Trait::new(ray_length * cos_ray, ray_length * sin_ray);
                let q1 = p1 + delta1;

                // Counter for inner loop: check each edge of Enemy for intersection this sensor's ray
                let mut edge: usize = 0;

                loop {
                    if edge >= 3 {
                        break ();
                    }

                    // Endpoints of edge
                    let p2 = enemy_vertices.at(edge);

                    let mut q2_idx = edge + 1;
                    if q2_idx == 4 {
                        q2_idx = 0;
                    }

                    let q2 = enemy_vertices.at(q2_idx);

                    if does_intersect(p1, q1, *p2, *q2) {
                        distances_to_obstacle
                            .append(distance_to_intersection(p1, q1, *p2, *q2, cos_ray, sin_ray));
                    } else {
                        distances_to_obstacle.append(FixedTrait::new(0, false));
                    }

                    edge += 1;
                };
            },
            Option::None(_) => {
                break ();
            }
        };
    };

    distances_to_obstacle
}

// TODO
fn distances_to_wall() {}

// TODO
fn collision_enemy_check() {}

// TODO
fn collision_wall_check() {}

// Cool algorithm - see pp. 4-10 at https://www.dcs.gla.ac.uk/~pat/52233/slides/Geometry1x1.pdf
// Determines if segments p1q1 and p2q2 intersect 
// Benchmark ~10k steps
fn does_intersect(p1: Vec2, q1: Vec2, p2: Vec2, q2: Vec2) -> bool {
    let orientation_a = orientation(p1, q1, p2);
    let orientation_b = orientation(p1, q1, q2);
    let orientation_c = orientation(p2, q2, p1);
    let orientation_d = orientation(p2, q2, q1);

    // Either proof 1 or 2 proves intersection
    // Proof 1: two conditions must be met
    if orientation_a != orientation_b && orientation_c != orientation_d {
        return true;
    }

    // Proof 2: three conditions must be met
    // All points are colinear, i.e. all orientations = 0
    (orientation_a == 1
        && orientation_b == 1
        && orientation_c == 1
        && orientation_d == 1
        && // x-projections overlap
        ((p2.x >= p1.x && p2.x <= q1.x)
            || (p2.x <= p1.x && p2.x >= q1.x)
            || (q2.x >= p1.x && q2.x <= q1.x)
            || (q2.x <= p1.x && q2.x >= q1.x))
        && // y-projections overlap
        ((p2.y >= p1.y && p2.y <= q1.y)
            || (p2.y <= p1.y && p2.y >= q1.y)
            || (q2.y >= p1.y && q2.y <= q1.y)
            || (q2.y <= p1.y && q2.y >= q1.y)))
}

// Orientation = sign of cross product of vectors (b - a) and (c - b)
// (simpler than what they do in link above)
fn orientation(a: Vec2, b: Vec2, c: Vec2) -> u8 {
    let ab = b - a;
    let bc = c - b;
    let cross_product = ab.cross(bc);
    if cross_product.mag > 0 {
        if !cross_product.sign {
            return 2;
        }

        return 0;
    }

    return 1;
}

// TODO finish
// Finds distance from p1 to intersection of segments p1q1 and p2q2
fn distance_to_intersection(
    p1: Vec2, q1: Vec2, p2: Vec2, q2: Vec2, cos_ray: Fixed, sin_ray: Fixed
) -> Fixed {
    // All enemy edges are either vertical or horizontal
    if p2.y == q2.y { // Enemy edge is horizontal
        if p2.y == p1.y { // Ray is colinear with enemy edge
            return comp::min((p2.x - p1.x).abs(), (q2.x - p1.x).abs());
        } else {
            return ((p2.y - p1.y) / cos_ray).abs();
        }
    } else { // Enemy edge is vertical
        if p2.x == p1.x { // Ray is colinear with enemy edge
            return comp::min((p2.y - p1.y).abs(), (q2.y - p1.y).abs());
        } else {
            return ((p2.x - p1.x) / sin_ray).abs();
        }
    }
}

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
                    length: FixedTrait::new_unscaled(32_u128, false),
                    width: FixedTrait::new_unscaled(16_u128, false),
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
    use dojo::world::Context;
    use drive_ai::Vehicle;

    use super::{Racer, distances_to_enemy};

    fn execute(ctx: Context, model: felt252) {
        let (racer, vehicle) = get !(ctx.world, model.into(), (Racer, Vehicle));
        let sensors = distances_to_enemy(vehicle, vehicle);

        let mut calldata = ArrayTrait::new();
        calldata.append(model);
        ctx.world.execute('move_enemies', calldata.span());
    // 1. Compute sensors
    // 2. Run model forward pass
    // let controls = execute!(ctx.world, car.model, Sensors.serialize());
    // 3. Update car state
    // 4. Run collision detection
    }
}
