use cubit::types::{Vec2, Vec2Trait};
use cubit::types::{Fixed, FixedTrait};
use cubit::math::trig;

#[derive(Component, Serde, Drop, Copy)]
struct Vehicle {
    // Current vehicle position
    position: Vec2,
    // Vehicle steer in radians -1/2π <= s <= 1/2π
    steer: Fixed,
    // Vehicle velocity 0 <= v <= 100
    speed: Fixed
}

#[derive(Serde, Drop)]
enum Direction {
    Straight: (),
    Left: (),
    Right: (),
}

#[derive(Serde, Drop)]
struct Controls {
    steer: Direction,
}

// 10 degrees in radians
const TURN_STEP: felt252 = 3219565583416749172;

trait VehicleTrait {
    fn control(ref self: Vehicle, controls: Controls);
    fn drive(ref self: Vehicle);
}

impl VehicleImpl of VehicleTrait {
    fn control(ref self: Vehicle, controls: Controls) {
        let delta = match controls.steer {
            Direction::Straight(()) => FixedTrait::from_felt(0),
            Direction::Left(()) => FixedTrait::from_felt(-1 * TURN_STEP),
            Direction::Right(()) => FixedTrait::from_felt(TURN_STEP),
        };

        // TODO: Assert bounds
        self.steer = self.steer + delta;
    }

    fn drive(ref self: Vehicle) {
        // Initial position
        let r_0 = self.position;

        // Velocity vector
        let x_comp = self.speed * trig::cos(self.steer);
        let y_comp = self.speed * trig::sin(self.steer);
        let v_0 = Vec2Trait::new(x_comp, y_comp);

        self.position = r_0 + v_0;
    }
}
