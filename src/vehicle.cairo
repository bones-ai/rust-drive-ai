use array::ArrayTrait;
use cubit::types::vec2::{Vec2, Vec2Trait};
use cubit::types::fixed::{Fixed, FixedTrait, FixedPrint, ONE_u128};
use cubit::math::trig;
use drive_ai::math;

#[derive(Component, Serde, Drop, Copy)]
struct Vehicle {
    // Current vehicle position
    position: Vec2,
    // Vehicle dimensions, stored in half-lengths
    length: Fixed,
    width: Fixed,
    // Vehicle steer in radians -1/2π <= s <= 1/2π
    steer: Fixed,
    // Vehicle velocity 0 <= v <= 100
    speed: Fixed
}

impl VehicleSerdeLen of dojo::SerdeLen<Vehicle> {
    #[inline(always)]
    fn len() -> usize {
        12
    }
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

// 10 degrees / pi/18 radians
const TURN_STEP: felt252 = 3219563738742341801;
const HALF_PI: felt252 = 28976077338029890953;

trait VehicleTrait {
    fn control(ref self: Vehicle, controls: Controls) -> bool;
    fn drive(ref self: Vehicle);
    fn vertices(self: @Vehicle) -> Span<Vec2>;
}

use debug::PrintTrait;

impl VehicleImpl of VehicleTrait {
    fn control(ref self: Vehicle, controls: Controls) -> bool {
        let delta = match controls.steer {
            Direction::Straight(()) => FixedTrait::from_felt(0),
            Direction::Left(()) => FixedTrait::from_felt(-1 * TURN_STEP),
            Direction::Right(()) => FixedTrait::from_felt(TURN_STEP),
        };

        // TODO: Assert bounds
        self.steer = self.steer + delta;

        (self.steer >= FixedTrait::from_felt(-1 * HALF_PI)
            && self.steer <= FixedTrait::from_felt(HALF_PI))
    }

    fn drive(ref self: Vehicle) {
        // Velocity vector
        let x_comp = self.speed * trig::sin_fast(self.steer);
        let y_comp = self.speed * trig::cos_fast(self.steer);
        let v_0 = Vec2Trait::new(x_comp, y_comp);

        self.position = self.position + v_0;
    }

    fn vertices(self: @Vehicle) -> Span<Vec2> {
        math::vertices(*self.position, *self.width, *self.length, *self.steer)
    }
}

#[cfg(test)]
mod tests {
    use debug::PrintTrait;
    use cubit::types::vec2::{Vec2, Vec2Trait};
    use cubit::types::fixed::{Fixed, FixedTrait, FixedPrint};
    use cubit::test::helpers::assert_precise;
    use array::SpanTrait;

    use super::{Vehicle, VehicleTrait, Controls, Direction, TURN_STEP};

    const TEN: felt252 = 184467440737095516160;

    #[test]
    #[available_gas(2000000)]
    fn test_control() {
        let mut vehicle = Vehicle {
            position: Vec2Trait::new(FixedTrait::from_felt(TEN), FixedTrait::from_felt(TEN)),
            width: FixedTrait::from_felt(TEN),
            length: FixedTrait::from_felt(TEN),
            steer: FixedTrait::new(0_u128, false),
            speed: FixedTrait::from_felt(TEN)
        };

        vehicle.control(Controls { steer: Direction::Left(()) });
        assert(vehicle.steer == FixedTrait::from_felt(-1 * TURN_STEP), 'invalid steer');
        vehicle.control(Controls { steer: Direction::Left(()) });
        assert(vehicle.steer == FixedTrait::from_felt(-2 * TURN_STEP), 'invalid steer');
        vehicle.control(Controls { steer: Direction::Right(()) });
        assert(vehicle.steer == FixedTrait::from_felt(-1 * TURN_STEP), 'invalid steer');
        vehicle.control(Controls { steer: Direction::Right(()) });
        assert(vehicle.steer == FixedTrait::from_felt(0), 'invalid steer');
    }

    #[test]
    #[available_gas(20000000)]
    fn test_drive() {
        let mut vehicle = Vehicle {
            position: Vec2Trait::new(FixedTrait::from_felt(TEN), FixedTrait::from_felt(TEN)),
            width: FixedTrait::from_felt(TEN),
            length: FixedTrait::from_felt(TEN),
            steer: FixedTrait::new(0_u128, false),
            speed: FixedTrait::from_felt(TEN)
        };

        vehicle.drive();

        assert_precise(vehicle.position.x, TEN, 'invalid position x', Option::None(()));
        assert_precise(
            vehicle.position.y, 368934881474199059390, 'invalid position y', Option::None(())
        );

        vehicle.control(Controls { steer: Direction::Left(()) });
        vehicle.drive();

        // x: ~8.263527, y: ~29.84807913671
        assert_precise(
            vehicle.position.x, 152435159473296002840, 'invalid position x', Option::None(())
        );
        assert_precise(
            vehicle.position.y, 550599003738036609070, 'invalid position y', Option::None(())
        );
    }
}
