use cubit::types::vec2::{Vec2, Vec2Trait};
use cubit::types::fixed::{Fixed, FixedTrait};

#[derive(Component, Serde, SerdeLen, Drop)]
struct Enemy {
    typ: u8, 
}

// Road dimensions
// 400x1000

#[system]
mod spawn_enemies {
    use traits::Into;
    use cubit::types::FixedTrait;
    use cubit::types::Vec2Trait;

    use dojo::world::Context;
    use drive_ai::Vehicle;

    use super::Enemy;

    fn execute(ctx: Context, model: felt252) {
        let position = Vec2Trait::new(
            FixedTrait::new_unscaled(50, false), FixedTrait::new_unscaled(0, false)
        );
        set !(
            ctx.world,
            ctx.world.uuid().into(),
            (Vehicle {
                position,
                length: FixedTrait::new_unscaled(16_u128, false),
                width: FixedTrait::new_unscaled(32_u128, false),
                speed: FixedTrait::new_unscaled(50_u128, false),
                steer: FixedTrait::new_unscaled(0_u128, false),
            })
        );

        return ();
    }
}

#[system]
mod move_enemies {
    use traits::Into;
    use cubit::types::FixedTrait;
    use cubit::types::Vec2Trait;

    use dojo::world::Context;
    use drive_ai::Vehicle;

    use super::Enemy;

    const PLAYERS: u8 = 10;
    const GRID_Y_SIZE: u128 = 1000;

    fn execute(ctx: Context, model: felt252) {
        // Iterate through the enemies and move them. If the are out of the grid respawn them at the top of the grid
        let mut i: u8 = 0;
        loop {
            if i == PLAYERS {
                break ();
            }
            let mut enemy = get !(ctx.world, i.into(), Enemy);
            // Enemy
            // +---+ 
            // |   | ^
            // | x | | length
            // |   | v
            // +---+ 
            // <-->
            // width
            //
            // We respawn the enemy if the front of the car has disappeared from the grid <=> center.y + length / 2 <= 0.
            // As we need to make this smooth for the ui we'll respawn the car at the top of the grid - distance
            // traveled during the tick.
            // Ex: If the center of the enemy is at the position init = (16, 25) and its speed is 50 points/tick
            // We'll respawn the car at (16, TOP_GRID - (speed - init.y) + length / 2).
            // We add length / 2 so that the rear of the car is at the top of the grid.
            let half_length = enemy.length / FixedTrait::new(2, false);
            let grid_height = FixedTrait::new(GRID_Y_SIZE, false);
            if enemy.position.y <= enemy.speed + half_length {
                enemy.position.y = grid_height - (enemy.speed - enemy.position.y) + half_length;
            } else {
                enemy.position.y -= enemy.speed;
            }
            set !(ctx.world, i.into(), (enemy));
            i += 1;
        }
    }
}
