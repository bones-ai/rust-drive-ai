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
