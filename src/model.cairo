#[system]
mod model {
    use cubit::types::FixedTrait;

    use dojo::world::Context;

    use drive_ai::car::Sensors;
    use drive_ai::car::Controls;

    fn execute(ctx: Context, sensors: Sensors) -> Controls {
        // TODO: Run model and predict controls

        Controls {
            steer: FixedTrait::new(0_u128, false),
            acc: FixedTrait::new(0_u128, false),
        }
    }
}
