/// Number of enemies to spawn.
const ENEMIES_NB: u8 = 10;
/// Height of the grid.
const GRID_HEIGHT: u128 = 1000;
// Width of the grid.
const GRID_WIDTH: u128 = 400;

const CAR_HEIGHT: u128 = 32;
const CAR_WIDTH: u128 = 16;
const CAR_VELOCITY: u128 = 50;

#[derive(Component, Serde, SerdeLen, Drop, Copy)]
struct Position {
    // Current vehicle position
    x: u128,
    y: u128,
}

#[system]
mod spawn_enemies {
    use integer::{u256_safe_divmod, u256_as_non_zero};
    use traits::Into;
    use array::{Array, ArrayTrait};
    use cubit::types::vec2::{Vec2, Vec2Trait};
    use cubit::types::FixedTrait;
    use dojo::world::Context;
    use drive_ai::Vehicle;
    use super::{Position, ENEMIES_NB, GRID_HEIGHT, GRID_WIDTH};

    /// Spawn the enemies provided in the array.
    /// /!\ Panics if the number of enemies provided in the array don't match the expected number
    /// of enemies defined in the [`super::ENEMIES_NB`] constant.
    /// There's no sanity check on any of the properties of the enemies so it's possible to spawn
    /// enemies with really high speed, on top of each other or too big for the grid.
    ///
    /// # Arguments
    ///
    /// * `ctx` - Context of the game.
    /// * `enemies` - Array of enemies. It is assumed that all the enemies in this array are valid.
    fn execute(ctx: Context, model: felt252) {
        let mut i: usize = 0;
        loop {
            if i == ENEMIES_NB.into() {
                break ();
            }

            let numerator: u256 = model.into() * i.into();
            let (_, x_rem) = u256_safe_divmod(numerator, u256_as_non_zero(GRID_WIDTH.into()));
            let (_, y_rem) = u256_safe_divmod(numerator, u256_as_non_zero(GRID_HEIGHT.into()));

            set !(ctx.world, (model, i).into(), (Position { x: x_rem.low, y: y_rem.low }));
            i += 1;
        }
    }
}

#[cfg(test)]
mod tests_spawn {
    use cubit::types::{FixedTrait, Vec2Trait};
    use traits::Into;
    use super::spawn_enemies::execute;
    use array::{Array, ArrayTrait};
    use dojo::world::IWorldDispatcherTrait;
    use super::{Position, ENEMIES_NB};
    use dojo::test_utils::spawn_test_world;

    #[test]
    #[available_gas(20000000000)]
    fn test_spawn() {
        // Get required component.
        let mut components = ArrayTrait::new();
        components.append(drive_ai::vehicle::vehicle::TEST_CLASS_HASH);
        // Get required system.
        let mut systems = ArrayTrait::new();
        systems.append(super::spawn_enemies::TEST_CLASS_HASH);
        // Get test world.
        let world = spawn_test_world(components, systems);

        let caller = starknet::contract_address_const::<0x0>();
        // The execute method from the spawn system expects a Vehicle array 
        // formatted as a felt252 array to spawn the enemies
        let mut calldata: Array<felt252> = ArrayTrait::new();
        // Model.
        calldata.append(1);
        world.execute('spawn_enemies'.into(), calldata.span());
        let mut i: usize = 0;
        let players: usize = ENEMIES_NB.into();
        loop {
            if i == players {
                break ();
            }
            // We set the model to 1 earlier.
            let position = world
                .entity('Position'.into(), (1, i).into(), 0, dojo::SerdeLen::<Position>::len());

            assert(*position[0] == i.into(), 'Wrong position x');
            assert(*position[1] == i.into(), 'Wrong position y');

            i += 1;
        }
    }
}

#[system]
mod move_enemies {
    use traits::Into;
    use cubit::types::{Fixed, FixedTrait};
    use cubit::types::Vec2Trait;

    use dojo::world::Context;

    use drive_ai::Vehicle;
    use super::{Position, CAR_HEIGHT, CAR_VELOCITY, ENEMIES_NB, GRID_HEIGHT};


    /// Executes a tick for the enemies.
    /// During a tick the enemies will need to be moved/respawned if they go out of the grid.
    ///
    /// # Argument
    ///
    /// * `ctx` - Context of the game.
    fn execute(ctx: Context, model: felt252) {
        // Iterate through the enemies and move them. If the are out of the grid respawn them at 
        // the top of the grid
        let mut i: u8 = 0;
        loop {
            if i == ENEMIES_NB {
                break ();
            }
            let position = get !(ctx.world, (model, i).into(), Position);
            let position = move(position, CAR_HEIGHT, CAR_VELOCITY);
            set !(ctx.world, (model, i).into(), (Position { x: position.x, y: position.y,  }));
            i += 1;
        }
    }

    /// Vehicle
    /// +---+ 
    /// |   | ^
    /// | x | | 2 * length
    /// |   | v
    /// +---+ 
    ///
    /// We respawn the enemy if the front of the car has disappeared from the grid
    /// <=> 
    /// center.y + length <= 0.
    /// As we need to make this smooth for the ui we'll respawn the car at the top of the grid - distance
    /// traveled during the tick.
    /// Ex: If the center of the enemy is at the position init = (16, 25) and its speed is 50 points/tick
    /// We'll respawn the car at (16, TOP_GRID - (speed - init.y) + length).
    ///
    /// # Argument
    ///
    /// * `enemy`- The enemy to move.
    #[inline(always)]
    fn move(position: Position, height: u128, velocity: u128) -> Position {
        let grid_height = GRID_HEIGHT;
        let y = position.y;
        let x = position.x;

        let new_y = if y <= velocity + height {
            grid_height - (velocity - y) + height
        } else {
            y - velocity
        };

        Position { x, y: new_y }
    }
}

#[cfg(test)]
mod tests_move {
    use cubit::types::{FixedTrait, Vec2Trait};
    use super::move_enemies::move;
    use super::Position;

    #[test]
    #[available_gas(2000000)]
    fn test_move_respawns_on_top() {
        let x = 16;
        let y = 25;
        let height = 10;
        let width = 1;
        let velocity = 50;
        let position = Position { x: x, y: y };
        // Top of the grid - (velocity - remaining bottom grid) + enemy height
        // 1000 - (50 - 25) + 10 = 985
        let expect_y = 985;

        let got_position = move(position, height, velocity);
        assert(got_position.x == x, 'Wrong position x');
        assert(got_position.y == expect_y, 'Wrong position y');
    }

    #[test]
    #[available_gas(2000000)]
    fn test_move_without_respawn() {
        let x = 16;
        let y = 980;
        let height = 10;
        let width = 1;
        let velocity = 50;
        let position = Position { x: x, y: y };
        // y - speed
        // 980 - 50 = 930
        let expect_y = 930;
        let expect_position = Position { x, y: expect_y };
        let got_position = move(position, height, velocity);

        assert(got_position.x == expect_position.x, 'Wrong position x');
        assert(got_position.y == expect_position.y, 'Wrong position y');
    }
}
