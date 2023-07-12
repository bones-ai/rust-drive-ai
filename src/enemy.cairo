/// Number of enemies to spawn.
const ENEMIES_NB: u8 = 10;
/// Height of the grid.
const GRID_HEIGHT: u128 = 1000;

// Road dimensions
// 400x1000

#[system]
mod spawn_enemies {
    use traits::Into;
    use array::{Array, ArrayTrait};
    use cubit::types::vec2::Vec2;
    use dojo::world::Context;
    use drive_ai::Vehicle;
    use super::ENEMIES_NB;

    /// Spawn the enemies provided in the array.
    /// /!\ Panics if the number of enemies provided in the array don't match the expected number
    /// of enemies defined in the [`suer::ENEMIES_NB`] constant.
    /// There's no sanity check on any of the properties of the enemies so it's possible to spawn
    /// enemies with really high speed, on top of each other or too big for the grid.
    ///
    /// # Arguments
    ///
    /// * `ctx` - Context of the game.
    /// * `enemies` - Array of enemies. It is assumed that all the enemies in this array are valid.
    fn execute(ctx: Context, enemies: Array<Vehicle>) {
        let enemies_len = enemies.len();
        assert(enemies_len == ENEMIES_NB.into(), 'Wrong enemies len provided');
        let mut i: usize = 0;
        loop {
            if i == ENEMIES_NB.into() {
                break ();
            }
            let enemy: Vehicle = *enemies[i];
            set !(
                ctx.world,
                i.into(),
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
    fn execute(ctx: Context) {
        // Iterate through the enemies and move them. If the are out of the grid respawn them at 
        // the top of the grid
        let mut i: u8 = 0;
        loop {
            if i == ENEMIES_NB {
                break ();
            }
            let enemy = get !(ctx.world, i.into(), Vehicle);
            let enemy = move_enemy(enemy);
            set !(
                ctx.world,
                i.into(),
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
    /// | x | | length
    /// |   | v
    /// +---+ 
    /// <-->
    /// width
    ///
    /// We respawn the enemy if the front of the car has disappeared from the grid
    /// <=> 
    /// center.y + length / 2 <= 0.
    /// As we need to make this smooth for the ui we'll respawn the car at the top of the grid - distance
    /// traveled during the tick.
    /// Ex: If the center of the enemy is at the position init = (16, 25) and its speed is 50 points/tick
    /// We'll respawn the car at (16, TOP_GRID - (speed - init.y) + length / 2).
    /// We add length / 2 so that the rear of the car is at the top of the grid.
    ///
    /// # Argument
    ///
    /// * `enemy`- The enemy to move.
    #[inline(always)]
    fn move_enemy(enemy: Vehicle) -> Vehicle {
        let half_length = FixedTrait::new(enemy.length.mag / 2, false);
        let grid_height = FixedTrait::new(GRID_HEIGHT, false);
        let new_y = if enemy.position.y <= enemy.speed + half_length {
            grid_height - (enemy.speed - enemy.position.y) + half_length
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
        // Top of the grid - (speed - remaining bottom grid) + enemy length / 2
        // 1000 - (50 - 25) + 5 = 980
        let expected_y = FixedTrait::new(980, false);
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
