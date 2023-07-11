#[system]
mod model {
    use array::ArrayTrait;

    use starknet::ContractAddress;

    use dojo::world::Context;

    use drive_ai::racer::Sensors;
    use drive_ai::vehicle::Controls;
    use drive_ai::vehicle::Direction;
    use drive_ai::nn::INNDispatcherTrait;
    use drive_ai::nn::INNDispatcher;

    fn execute(ctx: Context, sensors: Sensors, nn_address: ContractAddress) -> Controls {
        let prediction: usize = INNDispatcher {
            contract_address: nn_address
        }.forward(sensors.rays);

        let steer: Direction = if prediction == 0 {
            Direction::Straight(())
        } else if prediction == 1 {
            Direction::Left(())
        } else if prediction == 2 {
            Direction::Right(())
        } else {
            let mut panic_msg = ArrayTrait::new();
            panic_msg.append('prediction must be < 3');
            panic(panic_msg)
        };

        Controls { steer: steer,  }
    }
}
