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
                let delta1 = Vec2Trait::new(ray_length * sin_ray, ray_length * cos_ray);
                let q1 = p1 + delta1;

                // Counter for inner loop: check each edge of Enemy for intersection with this ray
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

#[cfg(test)]
mod tests {
    use debug::PrintTrait;
    use cubit::types::vec2::{Vec2, Vec2Trait};
    use cubit::types::fixed::{Fixed, FixedTrait, FixedPrint, ONE_u128};
    use cubit::test::helpers::assert_precise;
    use array::SpanTrait;
    use drive_ai::{Vehicle, VehicleTrait, Enemy};
    use super::Sensors;

    const RAY_LENGTH: u128 = 150;

    const TEN: felt252 = 184467440737095516160;
    const TWENTY: felt252 = 368934881474191032320;
    const TWENTY_FIVE: felt252 = 461168601842738790400;
    const THIRTY: felt252 = 553402322211286548480
    const FORTY: felt252 = 737869762948382064640;
    const FIFTY: felt252 = 922337203685477580800;
    const SIXTY: felt252 = 1106804644422573096960;
    const EIGHTY: felt252 = 1475739525896764129280;
    const HUNDRED: felt252 = 1844674407370955161600;
    
    const DEG_30_IN_RADS: felt252 = -9658715196994321226;
    const DEG_90_IN_RADS: felt252 = 28976077338029890953;

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


    #[test]
    #[available_gas(20000000)]
    fn test_does_intersect() {
        let mut p1 = Vec2Trait::new(FixedTrait::from_felt(0), FixedTrait::from_felt(TEN));
        let mut q1 = Vec2Trait::new(FixedTrait::from_felt(FORTY), FixedTrait::from_felt(THIRTY));
        let mut p2 = Vec2Trait::new(FixedTrait::from_felt(THIRTY), FixedTrait::from_felt(0));
        let mut q2 = Vec2Trait::new(FixedTrait::from_felt(TEN), FixedTrait::from_felt(FORTY));
        let intersect = does_intersect(p1, q1, p2, q2);
        assert(intersect == true, 'invalid intersection');

        q2 = Vec2Trait::new(FixedTrait::from_felt(TEN), FixedTrait::from_felt(TEN));
        intersect = does_intersect(p1, q1, p2, q2);
        assert(intersect == false, 'invalid non-intersection');

        q1 = Vec2Trait::new(FixedTrait::from_felt(THIRTY), FixedTrait::from_felt(TEN));
        p2 = Vec2Trait::new(FixedTrait::from_felt(TWENTY), FixedTrait::from_felt(TEN));
        q2 = Vec2Trait::new(FixedTrait::from_felt(FORTY), FixedTrait::from_felt(TEN));
        intersect = does_intersect(p1, q1, p2, q2);
        assert(intersect == true, 'invalid colinear intersection');
    }

    #[test]
    #[available_gas(20000000)]
    fn test_orientation() {
        let a = Vec2Trait::new(FixedTrait::from_felt(0), FixedTrait::from_felt(TEN));
        let b = Vec2Trait::new(FixedTrait::from_felt(TWENTY), FixedTrait::from_felt(TWENTY));
        let mut c = Vec2Trait::new(FixedTrait::from_felt(TEN), FixedTrait::from_felt(FORTY));
        let mut orientation = orientation(a, b, c);
        assert(orientation == 2_u8, 'invalid positive orientation');

        c = Vec2Trait::new(FixedTrait::from_felt(FORTY), FixedTrait::from_felt(THIRTY));
        orientation = orientation(a, b, c);
        assert(orientation == 1_u8, 'invalid zero orientation');

        c = Vec2Trait::new(FixedTrait::from_felt(THIRTY), FixedTrait::from_felt(ZERO));
        orientation = orientation(a, b, c);
        assert(orientation == 0_u8, 'invalid negative orientation');
    }

    #[test]
    #[available_gas(20000000)]
    fn test_distance_to_intersection() {
        let p1 = Vec2Trait::new(FixedTrait::from_felt(TEN), FixedTrait::from_felt(TWENTY));

        let ray_length = FixedTrait::from_felt(FORTY);
        let mut ray = FixedTrait::from_felt(DEG_30_IN_RADS);
        let mut cos_ray = trig::cos_fast(ray);
        let mut sin_ray = trig::sin_fast(ray);
        let mut delta1 = Vec2Trait::new(ray_length * sin_ray, ray_length * cos_ray);
        let mut q1 = p1 + delta1;
        let mut p2 = Vec2Trait::new(FixedTrait::from_felt(TWENTY), FixedTrait::from_felt(FIFTY));
        let mut q2 = Vec2Trait::new(FixedTrait::from_felt(FORTY), FixedTrait::from_felt(FIFTY));
        let mut distance = distance_to_intersection(p1, q1, p2, q2, cos_ray, sin_ray);
        // ~34.6410161513775
        assert_precise(distance.mag, 639013959397701000000, 'invalid distance horiz edge', Option::None(()));

        p2 = Vec2Trait::new(FixedTrait::from_felt(TWENTY_FIVE), FixedTrait::from_felt(FORTY));
        q2 = Vec2Trait::new(FixedTrait::from_felt(TWENTY_FIVE), FixedTrait::from_felt(SIXTY));
        distance = distance_to_intersection(p1, q1, p2, q2, cos_ray, sin_ray);
        // ~23.0940107675850
        assert_precise(distance.mag, 426009306265134000000, 'invalid distance vert edge', Option::None(()));

        ray = FixedTrait::from_felt(DEG_90_IN_RADS);
        cos_ray = trig::cos_fast(ray);
        sin_ray = trig::sin_fast(ray);
        delta1 = Vec2Trait::new(ray_length * sin_ray, ray_length * cos_ray);
        q1 = p1 + delta1;
        p2 = Vec2Trait::new(FixedTrait::from_felt(FORTY), FixedTrait::from_felt(TWENTY));
        q2 = Vec2Trait::new(FixedTrait::from_felt(SIXTY), FixedTrait::from_felt(TWENTY));
        distance = distance_to_intersection(p1, q1, p2, q2, cos_ray, sin_ray);
        // ~30.0
        assert_precise(distance.mag, 553402322211287000000, 'invalid distance colin-horiz edge', Option::None(()));

        ray = FixedTrait::from_felt(0);
        cos_ray = trig::cos_fast(ray);
        sin_ray = trig::sin_fast(ray);
        delta1 = Vec2Trait::new(ray_length * sin_ray, ray_length * cos_ray);
        q1 = p1 + delta1;
        p2 = Vec2Trait::new(FixedTrait::from_felt(TEN), FixedTrait::from_felt(FIFTY));
        q2 = Vec2Trait::new(FixedTrait::from_felt(TEN), FixedTrait::from_felt(EIGHTY));
        distance = distance_to_intersection(p1, q1, p2, q2, cos_ray, sin_ray);
        // ~30.0
        assert_precise(distance.mag, 553402322211287000000, 'invalid distance colin vert edge', Option::None(()));
    }
}
