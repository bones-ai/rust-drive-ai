use cubit::types::vec2::{Vec2, Vec2Trait};
use cubit::types::fixed::{Fixed, FixedTrait, ONE_u128};
use cubit::math::trig;
use starknet::ContractAddress;
use drive_ai::{Vehicle, VehicleTrait, Enemy, EnemyTrait};
use array::ArrayTrait;

#[derive(Component, Serde, SerdeLen, Drop, Copy)]
struct Racer {
    // Vehicle owner
    driver: ContractAddress,
    // Model system name
    model: felt252,
}

#[derive(Serde, Drop)]
struct Sensors {
    rays: Array<Fixed>, // not sure if we need this also?
    distances_to_obstacle: Array<Fixed>,
}

const NUM_RAYS: u128 = 9; // must be ODD integer
const RAYS_TOTAL_ANGLE_DEG: u128 = 140;
const RAY_LENGTH: u128 = 150;

trait SensorsTrait {
    fn distances_to_enemy(self: Sensors, vehicle: Vehicle, enemy: Enemy);
    fn distances_to_wall();
}

impl SensorsImpl of SensorsTrait {
    fn distances_to_enemy(self: Sensors, vehicle: Vehicle, enemy: Enemy) {
        // Empties then fills Sensors mutable array self.distances_to_obstacle for particular Enemy

        // First, empty self.distances_to_obstacle
        loop {
            if self.distances_to_obstacle.len() == 0 {
                break ();
            }
            self.distances_to_obstacle.pop_front();
        }

        let one = FixedTrait::new(ONE_u128, false);
        let ray_length = FixedTrait::new(RAY_LENGTH, false);
        let enemy_vertices = EnemyTrait::get_vertices(Enemy);

        // First sensor ray angle, used as "counter" for outer loop to go through sensors
        let mut ray_angle = first_ray_angle(vehicle);

        loop {
            // Endpoints of Ray
            let p1 = self.position;
            let delta1 = Vec2Trait::new(
                ray_length * trig::cos(ray_angle), ray_length * trig::sin(ray_angle)
            );
            let q1 = p1 + delta1;

            // Counter for inner loop: check each edge of Enemy for intersection this sensor's ray
            let mut edge: usize = 0;

            loop {
                // Endpoints of edge
                let p2 = match edge {
                    0 => enemy_vertices[0],
                    1 => enemy_vertices[1],
                    2 => enemy_vertices[2],
                    3 => enemy_vertices[3]
                };
                let q2 = match edge {
                    0 => enemy_vertices[1],
                    1 => enemy_vertices[2],
                    2 => enemy_vertices[3],
                    3 => enemy_vertices[0]
                };

                if do_segments_intersect(p1, q1, p2, q2) {
                    self.distances_to_obstacle.append(distance_to_intersection(p1, q1, p2, q2));
                } else {
                    self.distances_to_obstacle.append(FixedTrait::new(0, false));
                }

                edge += 1;

                if edge >= 3 {
                    break ();
                }
            }

            ray_angle += angle_between_rays;

            if ray_angle > -first_ray_angle(vehicle) {
                break ();
            }
        }
    }

    // TODO
    fn distance_to_wall() {}
}

// TODO
fn collision_enemy_check() {}
// TODO
fn collision_wall_check() {}

// maybe put this in cubit::math::trig?
fn deg_to_rad(theta_deg: Fixed) -> Fixed {
    let pi = FixedTrait::new(trig::PI_u128, false);
    let one_eighty = FixedTrait::new(180 * ONE_u128, false);
    theta_deg * pi / one_eighty
}

fn first_ray_angle(vehicle: Vehicle) -> Fixed {
    let two = FixedTrait::new_unscaled(2_u128, false);
    let rays_total_angle = deg_to_rad(FixedTrait::new(RAYS_TOTAL_ANGLE_DEG, false));
    let rays_half_angle = rays_total_angle / two;
    return self.steer - rays_half_angle;
}

// Cool algorithm - see pp. 4-10 at https://www.dcs.gla.ac.uk/~pat/52233/slides/Geometry1x1.pdf
// Determines if segments p1q1 and p2q2 intersect 
fn do_segments_intersect(p1: Vec2, q1: Vec2, p2: Vec2, q2: Vec2) -> bool {
    let orientation_a = orientation(p1, q1, p2);
    let orientation_b = orientation(p1, q1, q2);
    let orientation_c = orientation(p2, q2, p1);
    let orientation_d = orientation(p2, q2, q1);

    // Either proof 1 or 2 proves intersection
    // Proof 1: two conditions must be met
    if orientation_a != orientation_b && orientation_c != orientation_d {
        return true;
    } else {
        // Proof 2: three conditions must be met
        // All points are colinear, i.e. all orientations = 0
        if orientation_a == 0 && orientation_b == 0 && orientation_c == 0 && orientation_d == 0 {
            // x-projections overlap
            if (p2.x >= p1.x && p2.x <= q1.x)
                || (p2.x <= p1.x && p2.x >= q1.x)
                || (q2.x >= p1.x && q2.x <= q1.x)
                || (q2.x <= p1.x && q2.x >= q1.x) {
                // y-projections overlap
                if (p2.y >= p1.y && p2.y <= q1.y)
                    || (p2.y <= p1.y && p2.y >= q1.y)
                    || (q2.y >= p1.y && q2.y <= q1.y)
                    || (q2.y <= p1.y && q2.y >= q1.y) {
                    return true;
                }
            }
        }
    }
    return false;
}

// Orientation = sign of cross product of vectors (b - a) and (c - b)
// (simpler than what they do in link above)
fn orientation(a: Vec2, b: Vec2, c: Vec2) -> felt252 {
    let ab = b - a;
    let bc = c - b;
    let cross_product = ab.cross(bc);
    if cross_product.mag > 0 {
        if !cross_product.sign {
            return 1;
        } else {
            return -1;
        }
    }

    return 0;
}

// TODO finish
// Finds distance from p1 to intersection of segments p1q1 and p2q2
fn distance_to_intersection(p1: Vec2, q1: Vec2, p2: Vec2, q2: Vec2) -> Fixed {
    let two = FixedTrait::new_unscaled(2_u128, false);

    // difference in starting points
    let p_diff = Vec2Trait::new(p1.x - p2.x, p1.y - p2.y);

    let cross_product = p_diff.cross(q2);
    if cross_product == 0 { // p_diff and q2 are colinear
    //TODO find y-coordinate of intersection only
    } else {
        let t = (q2.x * (p1.y - p2.y) - q2.y * (p1.x - p2.x)) / determinant;

        let intersection = Vec2Trait::new(p1.x + t * (q1.x - p1.x), p1.y + t * (q1.y - p1.y));

        let partial_ray = intersection - p1;
    }

    return sqrt(partial_ray.x.pow(two) + partial_ray.y.pow(two));
}

#[system]
mod spawn_racer {
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
            ctx.world.uuid().into(),
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

        return ();
    }
}

#[system]
mod drive {
    use traits::Into;
    use dojo::world::Context;

    use super::Racer;
    use drive_ai::Vehicle;

    fn execute(ctx: Context, car: usize) {
        let (racer, vehicle) = get !(ctx.world, car.into(), (Racer, Vehicle));
    // 1. Compute sensors
    // 2. Run model forward pass
    // let controls = execute!(ctx.world, car.model, Sensors.serialize());
    // 3. Update car state
    // 4. Run collision detection
    }
}
