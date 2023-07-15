use array::ArrayTrait;
use cubit::types::vec2::Vec2;
use cubit::types::fixed::FixedTrait;

/// Number of enemies to spawn.
const ENEMIES_NB: u8 = 10;

// For this file, these const's should remain unscaled (?)

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

trait PositionTrait {
    /// Returns the vertices of the vehicle.
    fn vertices(self: @Position) -> Span<Vec2>;
}

impl PostionImpl of PositionTrait {
    fn vertices(self: @Position) -> Span<Vec2> {
        // TODO: Calculate values
        let mut vertices = ArrayTrait::new();
        vertices
            .append(
                Vec2 { x: FixedTrait::new(*self.x, false), y: FixedTrait::new(*self.y, false) }
            );
        vertices
            .append(
                Vec2 { x: FixedTrait::new(*self.x, false), y: FixedTrait::new(*self.y, false) }
            );
        vertices
            .append(
                Vec2 { x: FixedTrait::new(*self.x, false), y: FixedTrait::new(*self.y, false) }
            );
        vertices
            .append(
                Vec2 { x: FixedTrait::new(*self.x, false), y: FixedTrait::new(*self.y, false) }
            );
        vertices.span()
    }
}

#[system]
mod spawn_enemies {
    use integer::{u256_safe_divmod, u256_as_non_zero};
    use traits::{Into, TryInto};

    use dojo::world::Context;

    use drive_ai::Vehicle;
    use super::{Position, ENEMIES_NB, GRID_HEIGHT, GRID_WIDTH, CAR_WIDTH};

    /// Spawn [`ENEMIES_NB`] enemies. Each enemy has its own x range that corresponds to: 
    /// [`GRID_WIDTH`] * car_nb / [`ENEMIES_NB`] to [`GRID_WIDTH`] * (car_nb + 1) / [`ENEMIES_NB`]
    /// So they don't spawn on top of each other.
    /// The initial Y position is determined by model * car_nb / [GRID_HEIGHT] % GRID_HEIGHT 
    /// This division is a felt division so that cars don't spawn in diagonal and are well spread out
    ///
    /// # Arguments
    ///
    /// * `ctx` - Context of the game.
    /// * `model` - The AI model id to namespace the games.
    fn execute(ctx: Context, model: felt252) {
        let mut i: usize = 0;
        // Get the grid height as [`NonZero<felt252>`] for later div.
        let grid_height: felt252 = GRID_HEIGHT.into();
        // GRID_HEIGHT is a constant not set to 0 so it can't panic.
        let grid_height: NonZero<felt252> = grid_height.try_into().unwrap();
        // Get the grid height as [`NonZero<u256>`] for later div.
        // GRID_HEIGHT is a constant not set to 0 so it can't panic.
        let big_grid_height: NonZero<u256> = u256 {
            low: GRID_HEIGHT.into(), high: 0_u128
        }.try_into().unwrap();

        // ENEMIES_NB is a constant not set to 0 so it can't panic.
        let x_range: u128 = GRID_WIDTH.into() / ENEMIES_NB.into() - 2 * CAR_WIDTH.into();

        loop {
            if i == ENEMIES_NB.into() {
                break ();
            }
            let numerator: felt252 = model.into() + i.into();
            // This value gives us a """random""" value to better spread the enemies on the grid at init.
            let base_value = felt252_div(numerator, grid_height);
            // Resize the value so it fits in the x range given for enemies so they don't overlap.
            let (_, x_rem) = u256_safe_divmod(base_value.into(), u256_as_non_zero(x_range.into()));
            // Resize the value so it fits in the grid height.
            let (_, y_rem) = u256_safe_divmod(base_value.into(), big_grid_height);
            // Spawn the enemy.
            set !(
                ctx.world,
                (model, i).into(),
                (Position {
                    x: x_rem.low + CAR_WIDTH + (2 * CAR_WIDTH + x_range) * i.into(), y: y_rem.low
                })
            );
            i += 1;
        }
    }
}

#[cfg(test)]
mod tests_spawn {
    use array::{Array, ArrayTrait};
    use traits::Into;

    use dojo::test_utils::spawn_test_world;
    use dojo::world::IWorldDispatcherTrait;

    use super::{Position, ENEMIES_NB};

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
        let mut expected_coordinates: Array<felt252> = ArrayTrait::new();
        // 10 enemies on 400 width grid so each enemy has a 40 x range - the width 
        // of the car it's a range of 8
        // 16 <= x <= 24
        expected_coordinates.append(18);
        expected_coordinates.append(618);
        // 54 <= x <= 62
        expected_coordinates.append(60);
        expected_coordinates.append(236);
        // 96 <= x <= 104
        expected_coordinates.append(102);
        expected_coordinates.append(854);
        // 136 <= x <= 144
        expected_coordinates.append(136);
        expected_coordinates.append(472);
        // 176 <= x <= 184
        expected_coordinates.append(178);
        expected_coordinates.append(90);
        // 216 <= x <= 224
        expected_coordinates.append(220);
        expected_coordinates.append(708);
        // 256 <= x <= 264
        expected_coordinates.append(262);
        expected_coordinates.append(326);
        // 296 <= x <= 204
        expected_coordinates.append(296);
        expected_coordinates.append(944);
        // 336 <= x <= 344
        expected_coordinates.append(338);
        expected_coordinates.append(562);
        // 376 <= x <= 388
        expected_coordinates.append(380);
        expected_coordinates.append(180);

        loop {
            if i == players {
                break ();
            }
            // We set the model to 1 earlier.
            let position = world
                .entity('Position'.into(), (1, i).into(), 0, dojo::SerdeLen::<Position>::len());
            assert(*position[0] == *(@expected_coordinates)[2 * i], 'Wrong position x');
            assert(*position[1] == *(@expected_coordinates)[2 * i + 1], 'Wrong position y');
            i += 1;
        }
    }
}

#[system]
mod move_enemies {
    use integer::{u256_safe_divmod, u256_as_non_zero};
    use traits::{TryInto, Into};

    use dojo::world::Context;

    use super::{Position, CAR_HEIGHT, CAR_VELOCITY, ENEMIES_NB, GRID_HEIGHT, GRID_WIDTH, CAR_WIDTH};

    /// Executes a tick for the enemies.
    /// During a tick the enemies will need to be moved/respawned if they go out of the grid.
    ///
    /// # Arguments
    ///
    /// * `ctx` - Context of the game.
    /// * `model` - The AI model id to namespace the games.
    fn execute(ctx: Context, model: felt252) {
        // Iterate through the enemies and move them. If the are out of the grid respawn them at 
        // the top of the grid
        let mut i: u8 = 0;
        loop {
            if i == ENEMIES_NB {
                break ();
            }
            let key = (model, i).into();
            let position = get !(ctx.world, key, Position);
            let position = move(position, CAR_HEIGHT, CAR_VELOCITY, i.into());
            set !(ctx.world, key, (Position { x: position.x, y: position.y }));
            i += 1;
        }
    }

    /// Enemy
    /// +---+ 
    /// |   | ^
    /// | x | | 2 * length
    /// |   | v
    /// +---+ 
    /// <-->
    /// 2 * width
    /// We respawn the enemy if the front of the car has disappeared from the grid <=> center.y + length <= 0.
    /// As we need to make this smooth for the ui we'll respawn the car at the top of the 
    /// grid - distance traveled during the tick.
    /// Ex: If the center of the enemy is at the position init = (16, 25) and its speed is 50 points/tick
    /// We'll respawn the car at (16, TOP_GRID - (speed - init.y) + length).
    /// We also change the x coordinate of the enemy otherwise the racer would just drive straight forward.
    ///
    /// # Arguments
    ///
    /// * `position`- The initial position of the enemy to move.
    /// * `height` - The height of the enemy.
    /// * `velocity` - The velocity of the enemy to move.
    /// * `enemy_nb` - The enemy id that we want to move.
    ///
    /// # Returns
    ///
    /// * [`Position`] - The updated position of the enemy after being moved.
    #[inline(always)]
    fn move(position: Position, height: u128, velocity: u128, enemy_nb: u128) -> Position {
        let y = position.y;
        let x = position.x;

        // Get the grid width as [`NonZero<felt252>`] for later div.
        let grid_width: felt252 = GRID_WIDTH.into();
        // GRID_WIDTH is a constant not set to 0 so it can't panic.
        let grid_width: NonZero<felt252> = grid_width.try_into().unwrap();
        // ENEMIES_NB is a constant not set to 0 so it can't panic.
        let x_range: u128 = GRID_WIDTH.into() / ENEMIES_NB.into() - 2 * CAR_WIDTH.into();
        let base_value = felt252_div(x.into(), grid_width);
        let (_, x_rem) = u256_safe_divmod(base_value.into(), u256_as_non_zero(x_range.into()));
        let new_y = if y <= velocity + height {
            GRID_HEIGHT - (velocity - y) + height
        } else {
            y - velocity
        };

        Position {
            x: x_rem.low + CAR_WIDTH + (2 * CAR_WIDTH + x_range) * enemy_nb.into(), y: new_y
        }
    }
}

#[cfg(test)]
mod tests_move {
    use array::{Array, ArrayTrait};
    use traits::Into;

    use dojo::test_utils::spawn_test_world;
    use dojo::world::IWorldDispatcherTrait;

    use super::move_enemies::move;
    use super::{ENEMIES_NB, Position};
    use debug::PrintTrait;

    #[test]
    #[available_gas(2000000)]
    fn test_move_respawns_on_top() {
        let x = 16;
        let y = 25;
        let height = 10;
        let velocity = 50;
        let position = Position { x: x, y: y };

        // We change the x coordinate otherwise the racer would have to drive straight forward to win.
        let expected_x = 21;

        // Top of the grid - (velocity - remaining bottom grid) + enemy height
        // 1000 - (50 - 25) + 10 = 985
        let expected_y = 985;
        let got_position = move(position, height, velocity, 0);
        assert(got_position.x == expected_x, 'Wrong position x');
        assert(got_position.y == expected_y, 'Wrong position y');
    }

    #[test]
    #[available_gas(2000000)]
    fn test_move_without_respawn() {
        let x = 16;
        let y = 980;
        let height = 10;
        let velocity = 50;
        let position = Position { x: x, y: y };

        // We change the x coordinate otherwise the racer would have to drive straight forward to win.
        let expected_x = 61;
        // y - speed
        // 980 - 50 = 930
        let expected_y = 930;

        let got_position = move(position, height, velocity, 1);

        assert(got_position.x == expected_x, 'Wrong position x');
        assert(got_position.y == expected_y, 'Wrong position y');
    }

    #[test]
    #[available_gas(20000000000)]
    fn test_move_through_execute() {
        // Get required component.
        let mut components = ArrayTrait::new();
        components.append(drive_ai::vehicle::vehicle::TEST_CLASS_HASH);
        // Get required system.
        let mut systems = ArrayTrait::new();
        systems.append(super::spawn_enemies::TEST_CLASS_HASH);
        systems.append(super::move_enemies::TEST_CLASS_HASH);
        // Get test world.
        let world = spawn_test_world(components, systems);

        let caller = starknet::contract_address_const::<0x0>();
        // The execute method from the spawn system expects a Vehicle array 
        // formatted as a felt252 array to spawn the enemies
        let mut calldata: Array<felt252> = ArrayTrait::new();
        // Model.
        calldata.append(1);
        world.execute('spawn_enemies'.into(), calldata.span());
        world.execute('move_enemies'.into(), calldata.span());
        world.execute('move_enemies'.into(), calldata.span());
        let mut i: usize = 0;
        let players: usize = ENEMIES_NB.into();
        let mut expected_coordinates: Array<felt252> = ArrayTrait::new();
        // 10 enemies on 400 width grid so each enemy has a 40 x range - the width 
        // of the car it's a range of 8
        // 16 <= x <= 24
        expected_coordinates.append(23);
        // spawn_y - 50 = 618 - 50
        expected_coordinates.append(518);

        // 54 <= x <= 62
        expected_coordinates.append(58);
        // spawn_y - 50 = 236 - 50
        expected_coordinates.append(136);

        // 96 <= x <= 104
        expected_coordinates.append(103);
        // spawn_y - 50 = 854 - 50
        expected_coordinates.append(754);

        // 136 <= x <= 144
        expected_coordinates.append(138);
        // spawn_y - 50 = 472 - 50
        expected_coordinates.append(372);

        // 176 <= x <= 184
        expected_coordinates.append(183);
        // spawn_y - 50 = 90 - 50
        expected_coordinates.append(1022);

        // 216 <= x <= 224
        expected_coordinates.append(219);
        // spawn_y - 50 = 708 - 50
        expected_coordinates.append(608);

        // 256 <= x <= 264
        expected_coordinates.append(260);
        // spawn_y - 50 = 326 - 50
        expected_coordinates.append(226);

        // 296 <= x <= 304
        expected_coordinates.append(299);
        // spawn_y - 50 = 944 - 50
        expected_coordinates.append(844);

        // 336 <= x <= 344
        expected_coordinates.append(342);
        // spawn_y - 50 = 562 - 50
        expected_coordinates.append(462);

        // 376 <= x <= 388
        expected_coordinates.append(379);
        // spawn_y - 50 = 180 - 50
        expected_coordinates.append(80);
        loop {
            if i == players {
                break ();
            }
            // We set the model to 1 earlier.
            let position = world
                .entity('Position'.into(), (1, i).into(), 0, dojo::SerdeLen::<Position>::len());

            assert(*position[0] == *(@expected_coordinates)[2 * i], 'Wrong position x');
            assert(*position[1] == *(@expected_coordinates)[2 * i + 1], 'Wrong position y');
            i += 1;
        }
    }
}
