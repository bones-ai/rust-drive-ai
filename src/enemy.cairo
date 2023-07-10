use cubit::types::Vec2;
use cubit::types::Fixed;

#[derive(Component, Serde, Drop)]
struct Enemy {
    position: Vec2,
    velcity: Fixed,
}

impl EnemySerdeLen of dojo::SerdeLen<Enemy> {
    #[inline(always)]
    fn len() -> usize {
        3
    }
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
                steer: FixedTrait::new(0_u128, false),
                speed: FixedTrait::new(50_u128, false),
            })
        );

        return ();
    }
}
