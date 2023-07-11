#[system]
mod model {
    use cubit::types::FixedTrait;

    use dojo::world::Context;

    use drive_ai::racer::Sensors;
    use drive_ai::vehicle::Controls;
    use drive_ai::vehicle::Direction;

    fn execute(ctx: Context, sensors: Sensors) -> Controls {
        // TODO: Run model and predict controls

        Controls { steer: Direction::Straight(()),  }
    }
}
