use cubit::types::Vec2;
use cubit::types::Fixed;
use starknet::ContractAddress;

#[derive(Component, Serde, Drop, Copy)]
struct Car {
    // Current vehicle position
    position: Vec2,
    // Vehicle steer in degrees -90 <= s <= 90
    steer: Fixed,
    // Vehicle velocity 0 <= v <= 100
    speed: Fixed,
    // Vehicle owner
    driver: ContractAddress,
    // Model system name
    model: felt252,
}

#[derive(Serde, Drop)]
struct Sensors {
    rays: Array<Fixed>,
}

#[derive(Serde, Drop)]
struct Controls {
    steer: Fixed,
    acc: Fixed,
}

#[system]
mod spawn {
    use traits::Into;
    use cubit::types::FixedTrait;
    use cubit::types::Vec2Trait;

    use dojo::world::Context;

    use super::Car;

    fn execute(ctx: Context, model: felt252) {
        let position = Vec2Trait::new(
            FixedTrait::new_unscaled(50, false),
            FixedTrait::new_unscaled(0, false)
        );
        set!(
            ctx.world, ctx.world.uuid().into(), (Car {
                position,
                steer: FixedTrait::new(0_u128, false),
                speed: FixedTrait::new(50_u128, false),
                driver: ctx.origin,
                model
            })
        );

        return ();
    }
}

#[system]
mod drive {
    use traits::Into;
    use dojo::world::Context;

    use super::Car;

    fn execute(ctx: Context, car: usize) {
        let car = get!(ctx.world, car.into(), Car);
        
        // 1. Compute sensors
        // 2. Run model forward pass
        // let controls = execute!(ctx.world, car.model, Sensors.serialize());
        // 3. Update car state
        // 4. Run collision detection
    }
}
