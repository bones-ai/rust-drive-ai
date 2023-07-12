/// Number of enemies to spawn.
const ENEMIES_NB: u8 = 10;
/// Height of the grid.
const GRID_HEIGHT: u128 = 1000;
const GRID_WIDTH: u128 = 400;

// Road dimensions
// 400x1000

#[system]
mod spawn_enemies {
    use integer::{u256_safe_divmod, u256_as_non_zero};
    use traits::Into;
    use array::{Array, ArrayTrait};
    use cubit::types::vec2::{Vec2, Vec2Trait};
    use cubit::types::FixedTrait;
    use dojo::world::Context;
    use drive_ai::Vehicle;
    use super::{ENEMIES_NB, GRID_HEIGHT, GRID_WIDTH};

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
        let length = FixedTrait::new(32_u128, false);
        let width = FixedTrait::new(16_u128, false);
        let steer = FixedTrait::new(0_u128, false);
        let speed = FixedTrait::new(50_u128, false);

        let mut i: usize = 0;
        loop {
            if i == ENEMIES_NB.into() {
                break ();
            }

            let numerator: u256 = model.into() * i.into();
            let (_, x_rem) = u256_safe_divmod(numerator, u256_as_non_zero(GRID_WIDTH.into()));
            let (_, y_rem) = u256_safe_divmod(numerator, u256_as_non_zero(GRID_HEIGHT.into()));

            let position = Vec2Trait::new(
                FixedTrait::new(x_rem.low, false), FixedTrait::new(y_rem.low, false)
            );

            set !(
                ctx.world, (model, i).into(), (Vehicle { position, length, width, steer, speed,  })
            );
            i += 1;
        }
    }
}

#[cfg(test)]
mod tests_spawn {
    use cubit::types::{FixedTrait, Vec2Trait};
    use drive_ai::Vehicle;
    use traits::Into;
    use super::spawn_enemies::execute;
    use array::{Array, ArrayTrait};
    use dojo::world::IWorldDispatcherTrait;
    use super::ENEMIES_NB;
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
            let enemy = world
                .entity('Vehicle'.into(), (1, i).into(), 0, dojo::SerdeLen::<Vehicle>::len());
            let expected_length = 32_felt252;
            let expected_width = 16_felt252;
            let expected_steer = 0_felt252;
            let expected_speed = 50_felt252;

            assert(*enemy[0] == i.into(), 'Wrong position x');
            assert(*enemy[2] == i.into(), 'Wrong position y');
            assert(*enemy[4] == expected_length, 'Wrong length');
            assert(*enemy[6] == expected_width, 'Wrong width');
            assert(*enemy[8] == expected_steer, 'Wrong steer');
            assert(*enemy[10] == expected_speed, 'Wrong speed');

            i += 1;
        }
    }
}

#[system]
mod move_enemies {
    use traits::Into;
    use cubit::types::FixedTrait;
    use cubit::types::Vec2Trait;

    use dojo::world::Context;

    use drive_ai::Vehicle;
    use super::{ENEMIES_NB, GRID_HEIGHT};


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
            let enemy = get !(ctx.world, (model, i).into(), Vehicle);
            let enemy = move_enemy(enemy);
            set !(
                ctx.world,
                (model, i).into(),
                (Vehicle {
                    position: enemy.position,
                    length: enemy.length,
                    width: enemy.width,
                    steer: enemy.steer,
                    speed: enemy.speed,
                })
            );
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
    fn move_enemy(enemy: Vehicle) -> Vehicle {
        let grid_height = FixedTrait::new(GRID_HEIGHT, false);
        let new_y = if enemy.position.y <= enemy.speed + enemy.length {
            grid_height - (enemy.speed - enemy.position.y) + enemy.length
        } else {
            enemy.position.y - enemy.speed
        };
        let new_position = Vec2Trait::new(enemy.position.x, new_y);
        Vehicle {
            position: new_position,
            length: enemy.length,
            width: enemy.width,
            steer: enemy.steer,
            speed: enemy.speed,
        }
    }
}

#[cfg(test)]
mod tests_move {
    use cubit::types::{FixedTrait, Vec2Trait};
    use drive_ai::Vehicle;
    use super::move_enemies::move_enemy;

    fn get_test_enemy(x: u128, y: u128) -> Vehicle {
        let position = Vec2Trait::new(FixedTrait::new(x, false), FixedTrait::new(y, false));
        let length = FixedTrait::new(10, false);
        let width = FixedTrait::one();
        let steer = FixedTrait::new(0, false);
        let speed = FixedTrait::new(50, false);
        Vehicle { position: position, length: length, width: width, steer: steer, speed: speed,  }
    }

    #[test]
    #[available_gas(2000000)]
    fn test_move_enemy_respawns_on_top() {
        let x = 16;
        let y = 25;
        let enemy = get_test_enemy(:x, :y);
        // Top of the grid - (speed - remaining bottom grid) + enemy length
        // 1000 - (50 - 25) + 10 = 985
        let expected_y = FixedTrait::new(985, false);
        let expected_position = Vec2Trait::new(FixedTrait::new(x, false), expected_y);
        let expected_enemy = Vehicle {
            position: expected_position,
            length: enemy.length,
            width: enemy.width,
            steer: enemy.steer,
            speed: enemy.speed,
        };
        let updated_enemy = move_enemy(enemy);
        assert(updated_enemy.position.x == expected_enemy.position.x, 'Wrong position x');
        assert(updated_enemy.position.y == expected_enemy.position.y, 'Wrong position y');
        assert(updated_enemy.length == expected_enemy.length, 'Wrong length');
        assert(updated_enemy.width == expected_enemy.width, 'Wrong width');
        assert(updated_enemy.steer == expected_enemy.steer, 'Wrong steer');
        assert(updated_enemy.speed == expected_enemy.speed, 'Wrong speed');
    }

    #[test]
    #[available_gas(2000000)]
    fn test_move_enemy_without_respawn() {
        let x = 16;
        let y = 980;
        let enemy = get_test_enemy(:x, :y);
        // y - speed
        // 980 - 50 = 930
        let expected_y = FixedTrait::new(930, false);
        let expected_position = Vec2Trait::new(FixedTrait::new(x, false), expected_y);
        let expected_enemy = Vehicle {
            position: expected_position,
            length: enemy.length,
            width: enemy.width,
            steer: enemy.steer,
            speed: enemy.speed,
        };
        let updated_enemy = move_enemy(enemy);

        assert(updated_enemy.position.x == expected_enemy.position.x, 'Wrong position x');
        assert(updated_enemy.position.y == expected_enemy.position.y, 'Wrong position y');
        assert(updated_enemy.length == expected_enemy.length, 'Wrong length');
        assert(updated_enemy.width == expected_enemy.width, 'Wrong width');
        assert(updated_enemy.steer == expected_enemy.steer, 'Wrong steer');
        assert(updated_enemy.speed == expected_enemy.speed, 'Wrong speed');
    }
}
