use cubit::types::Vec2;
use cubit::types::Fixed;
use starknet::ContractAddress;

#[derive(Component, Serde, Drop, Copy)]
struct Racer {
    // Vehicle owner
    driver: ContractAddress,
    // Model system name
    model: felt252,
}

#[derive(Serde, Drop)]
struct Sensors {
    rays: Array<Fixed>, 
}

#[system]
mod spawn_racer {
    use traits::Into;
    use cubit::types::FixedTrait;
    use cubit::types::Vec2Trait;

    use dojo::world::Context;
    use drive_ai::Vehicle;

    use super::Racer;

    fn execute(ctx: Context, model: felt252) {
        let position = Vec2Trait::new(
            FixedTrait::new_unscaled(50, false), FixedTrait::new_unscaled(0, false)
        );
        set !(
            ctx.world,
            ctx.world.uuid().into(),
            (
                Racer {
                    driver: ctx.origin, model
                    }, Vehicle {
                    position,
                    steer: FixedTrait::new(0_u128, false),
                    speed: FixedTrait::new(50_u128, false),
                }
            )
        );

        return ();
    }
}

#[system]
mod drive {
    use traits::Into;
    use dojo::world::Context;

    use super::Racer;
    use drive_ai::Vehicle;

    fn execute(ctx: Context, car: usize) {
        let (racer, vehcile) = get !(ctx.world, car.into(), (Racer, Vehicle));
    // 1. Compute sensors
    // 2. Run model forward pass
    // let controls = execute!(ctx.world, car.model, Sensors.serialize());
    // 3. Update car state
    // 4. Run collision detection
    }
}