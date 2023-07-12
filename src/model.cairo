use orion::operators::tensor::core::Tensor;
use orion::numbers::fixed_point::core::FixedType;

#[starknet::interface]
trait INN<T> {
    #[view]
    fn forward(self: @T, input: Tensor<FixedType>) -> usize;
}

#[system]
mod model {
    use array::ArrayTrait;
    use starknet::ContractAddress;
    use dojo::world::Context;
    use drive_ai::racer::Sensors;
    use drive_ai::vehicle::{Controls, Direction};
    use super::{INNDispatcherTrait, INNDispatcher};

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


#[cfg(test)]
mod tests {
    use array::ArrayTrait;
    use traits::{TryInto, Into};
    use option::OptionTrait;
    use starknet::syscalls::deploy_syscall;
    use starknet::{ContractAddress, Felt252TryIntoContractAddress, ContractAddressIntoFelt252};
    use drive_ai::mock::nn::nn_mock;
    use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait, world};
    use dojo::executor::executor;
    use dojo::test_utils::spawn_test_world;

    use orion::operators::tensor::implementations::impl_tensor_fp::Tensor_fp;
    use orion::operators::tensor::core::{TensorTrait, ExtraParams};
    use orion::numbers::fixed_point::core::FixedTrait;
    use orion::numbers::fixed_point::implementations::impl_16x16::FP16x16Impl;
    use super::{model, Tensor, FixedType};
    use core::result::ResultTrait;
    use core::serde::Serde;
    use clone::Clone;

    #[test]
    #[available_gas(30000000)]
    fn test_model() {
        let caller = starknet::contract_address_const::<0x0>();

        let nn_constructor_calldata = array::ArrayTrait::new();
        let (nn_address, _) = deploy_syscall(
            class_hash: nn_mock::TEST_CLASS_HASH.try_into().unwrap(),
            contract_address_salt: 0,
            calldata: nn_constructor_calldata.span(),
            deploy_from_zero: false
        )
            .unwrap();

        // components
        let mut components = array::ArrayTrait::new();
        //systems
        let mut systems = array::ArrayTrait::new();
        systems.append(model::TEST_CLASS_HASH);

        // deploy executor, world and register components/systems
        let world = spawn_test_world(components, systems);

        let spawn_call_data = array::ArrayTrait::new();
        world.execute('spawn'.into(), spawn_call_data.span()); // Panics here: Deployed contract not found in registry

        let sensors = create_sensors();
        let mut model_call_data = sensors.span().snapshot.clone();
        model_call_data.append(nn_address.into());
        world.execute('model'.into(), model_call_data.span());
    //TODO: check result. 
    }

    // Utils
    fn create_sensors() -> Array<felt252> {
        let mut shape = ArrayTrait::<usize>::new();
        shape.append(5);
        let mut data = ArrayTrait::<FixedType>::new();
        data.append(FixedTrait::new_unscaled(1, false));
        data.append(FixedTrait::new_unscaled(2, false));
        data.append(FixedTrait::new_unscaled(3, false));
        data.append(FixedTrait::new_unscaled(4, false));
        data.append(FixedTrait::new_unscaled(5, false));
        let extra = Option::<ExtraParams>::None(());
        let tensor = TensorTrait::new(shape.span(), data.span(), extra);
        let mut serialized = ArrayTrait::new();
        tensor.serialize(ref serialized);
        serialized
    }
}

