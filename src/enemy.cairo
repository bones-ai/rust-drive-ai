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
