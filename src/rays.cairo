use cubit::math::trig;
use cubit::types::vec2::{Vec2, Vec2Trait};
use cubit::types::fixed::{Fixed, FixedTrait};
use array::{ArrayTrait, SpanTrait};

use drive_ai::math::{distance, intersects};

const DEG_90_IN_RADS: u128 = 28976077338029890953;
const DEG_70_IN_RADS: u128 = 22536387234850959209;
const DEG_50_IN_RADS: u128 = 16098473553126325695;
const DEG_30_IN_RADS: u128 = 9658715196994321226;
const DEG_10_IN_RADS: u128 = 3218956840862316756;

const RAY_LENGTH: u128 = 2767011611056432742400; // 150

#[derive(Serde, Drop)]
struct Rays {
    segments: Span<Ray>, 
}

trait RaysTrait {
    fn new(position: Vec2, theta: Fixed) -> Rays;
}

impl RaysImpl of RaysTrait {
    fn new(position: Vec2, theta: Fixed) -> Rays {
        // TODO optimization idea, something like 
        // `sensor_deltas: Array<(Array<(Fixed, Fixed, Vec2), Array<Vec2)>>`
        // 1) Outer array holds tuple of inner arrays, one for each possible `steer` angle 
        //    (if in 10 degree increments, or whatever size)
        // 2) First inner array, for particular `steer` angle, holds tuple of 
        //    precalculated `cos_theta`, `sin_theta`, and `delta1` values for each sensor. 
        // 3) Grab array corresponding to current steer value. If 17 possible steer.abs() values (0, 10, … , 160) using:
        //    `sensor_deltas_idx: usize = (steer.abs() / FixedTrait::new(TEN, false)).into()`
        //    if steer >= 0, use delta1 values as-is
        //    else use new_delta1.x = -delta1.x
        // 4) Second inner array holds precalculated rotated relative vertices for each steer angle
        //    (`rot_rel_vertex_0` and `rot_rel_vertex_1` in math.cairo)

        let ray_length = FixedTrait::new(RAY_LENGTH, false);

        let mut rays_theta = ArrayTrait::new();
        // rays_theta.append(theta - FixedTrait::new(DEG_70_IN_RADS, true));
        rays_theta.append(theta - FixedTrait::new(DEG_50_IN_RADS, true));
        rays_theta.append(theta - FixedTrait::new(DEG_30_IN_RADS, true));
        // rays_theta.append(theta - FixedTrait::new(DEG_10_IN_RADS, true));
        rays_theta.append(theta);
        // rays_theta.append(theta - FixedTrait::new(DEG_10_IN_RADS, false));
        rays_theta.append(theta - FixedTrait::new(DEG_30_IN_RADS, false));
        rays_theta.append(theta - FixedTrait::new(DEG_50_IN_RADS, false));
        // rays_theta.append(theta - FixedTrait::new(DEG_70_IN_RADS, false));

        // TODO: Rays are semetric, we calculate half and invert
        let mut segments = ArrayTrait::new();
        loop {
            match rays_theta.pop_front() {
                Option::Some(theta) => {
                    // Endpoints of Ray
                    // TODO: Rays are semetric, we calculate half and invert
                    let cos_theta = trig::cos_fast(theta);
                    let sin_theta = trig::sin_fast(theta);
                    let delta1 = Vec2Trait::new(ray_length * sin_theta, ray_length * cos_theta);

                    // TODO: We currently project out the center point?
                    let q = position + delta1;

                    segments.append(Ray { theta, cos_theta, sin_theta, p: position, q,  });
                },
                Option::None(_) => {
                    break ();
                }
            };
        };

        Rays { segments: segments.span() }
    }
}

#[derive(Serde, Drop)]
struct Ray {
    theta: Fixed,
    cos_theta: Fixed,
    sin_theta: Fixed,
    p: Vec2,
    q: Vec2,
}

trait RayTrait {
    fn intersects(self: @Ray, p: Vec2, q: Vec2) -> bool;
    fn dist(self: @Ray, p: Vec2, q: Vec2) -> Fixed;
}

impl RayImpl of RayTrait {
    fn intersects(self: @Ray, p: Vec2, q: Vec2) -> bool {
        intersects(*self.p, *self.q, p, q)
    }
    fn dist(self: @Ray, p: Vec2, q: Vec2) -> Fixed {
        distance(*self.p, p, q, *self.cos_theta, *self.sin_theta)
    }
}
