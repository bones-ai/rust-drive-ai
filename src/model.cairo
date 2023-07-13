use orion::operators::tensor::core::Tensor;
use orion::numbers::fixed_point::core::FixedType;

#[system]
mod model {
    use array::ArrayTrait;
    use starknet::ContractAddress;
    use dojo::world::Context;
    use drive_ai::racer::Sensors;
    use drive_ai::vehicle::{Controls, Direction};

    use orion::operators::nn::core::NNTrait;
    use orion::operators::nn::implementations::impl_nn_i8::NN_i8;
    use orion::operators::tensor::core::{TensorTrait, ExtraParams, Tensor};
    use orion::operators::tensor::implementations::impl_tensor_fp::Tensor_fp;
    use orion::operators::tensor::implementations::impl_tensor_i8::Tensor_i8;
    use orion::numbers::signed_integer::i8::i8;
    use orion::numbers::fixed_point::core::{FixedType, FixedTrait};
    use orion::numbers::fixed_point::implementations::impl_16x16::FP16x16Impl;
    use orion::performance::core::PerfomanceTrait;
    use orion::performance::implementations::impl_performance_fp::Performance_fp_i8;

    fn execute(ctx: Context, sensors: Sensors) -> Controls {
        let prediction: usize = forward(sensors.rays);

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

    fn forward(input: Tensor<FixedType>) -> usize {
        let w = fc1::fc1_weights();
        let b = fc1::fc1_bias();

        // YSCALE
        let mut shape = ArrayTrait::<usize>::new();
        shape.append(1);
        let mut data = ArrayTrait::<FixedType>::new();
        data.append(FixedTrait::new_unscaled(1, false));
        let extra = Option::<ExtraParams>::None(());
        let y_scale = TensorTrait::new(shape.span(), data.span(), extra);

        // ZEROPOINT
        let mut shape = ArrayTrait::<usize>::new();
        shape.append(1);
        let mut data = ArrayTrait::<FixedType>::new();
        data.append(FixedTrait::new_unscaled(0, false));
        let extra = Option::<ExtraParams>::None(());
        let y_zero_point = TensorTrait::new(shape.span(), data.span(), extra);

        let x = input.quantize_linear(@y_scale, @y_zero_point);
        let x = NNTrait::linear(x, w, b);
        *x.argmax(0, Option::None(()), Option::None(())).data[0]
    }

    mod fc1 {
        use array::ArrayTrait;
        use orion::operators::tensor::core::{TensorTrait, Tensor, ExtraParams};
        use orion::operators::tensor::implementations::impl_tensor_i8::Tensor_i8;
        use orion::numbers::fixed_point::core::FixedImpl;
        use orion::numbers::signed_integer::i8::i8;

        fn fc1_weights() -> Tensor<i8> {
            let mut shape = ArrayTrait::<usize>::new();
            shape.append(3);
            shape.append(5);
            let mut data = ArrayTrait::new();
            data.append(i8 { mag: 1, sign: true });
            data.append(i8 { mag: 2, sign: false });
            data.append(i8 { mag: 3, sign: false });
            data.append(i8 { mag: 4, sign: true });
            data.append(i8 { mag: 5, sign: true });
            data.append(i8 { mag: 1, sign: false });
            data.append(i8 { mag: 2, sign: false });
            data.append(i8 { mag: 3, sign: false });
            data.append(i8 { mag: 4, sign: true });
            data.append(i8 { mag: 1, sign: true });
            data.append(i8 { mag: 2, sign: false });
            data.append(i8 { mag: 3, sign: false });
            data.append(i8 { mag: 4, sign: false });
            data.append(i8 { mag: 1, sign: true });
            data.append(i8 { mag: 2, sign: true });
            let extra = Option::<ExtraParams>::None(());
            TensorTrait::new(shape.span(), data.span(), extra)
        }

        fn fc1_bias() -> Tensor<i8> {
            let mut shape = ArrayTrait::<usize>::new();
            shape.append(3);
            let mut data = ArrayTrait::new();
            data.append(i8 { mag: 1, sign: false });
            data.append(i8 { mag: 2, sign: true });
            data.append(i8 { mag: 3, sign: true });
            let extra = Option::<ExtraParams>::None(());
            TensorTrait::new(shape.span(), data.span(), extra)
        }
    }
}


#[cfg(test)]
mod tests {
    use core::result::ResultTrait;
    use core::serde::Serde;
    use clone::Clone;
    use array::ArrayTrait;
    use traits::{TryInto, Into};
    use option::OptionTrait;
    use starknet::syscalls::deploy_syscall;
    use starknet::{ContractAddress, Felt252TryIntoContractAddress, ContractAddressIntoFelt252};

    use drive_ai::racer::Sensors;

    use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait, world};
    use dojo::test_utils::spawn_test_world;

    use orion::operators::tensor::implementations::impl_tensor_fp::Tensor_fp;
    use orion::operators::tensor::core::{TensorTrait, ExtraParams};
    use orion::numbers::fixed_point::core::FixedTrait;
    use orion::numbers::fixed_point::implementations::impl_16x16::FP16x16Impl;

    use super::{model, Tensor, FixedType};


    #[test]
    #[available_gas(30000000)]
    fn test_model() {
        let caller = starknet::contract_address_const::<0x0>();

        // Get required component.
        let mut components = array::ArrayTrait::new();
        // components.append(drive_ai::vehicle::vehicle::TEST_CLASS_HASH);
        // Get required system.
        let mut systems = array::ArrayTrait::new();
        systems.append(model::TEST_CLASS_HASH);
        // Get test world.
        let world = spawn_test_world(components, systems);
        let sensors = create_sensors();
        world.execute('model'.into(), sensors.span());
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
        let rays = TensorTrait::new(shape.span(), data.span(), extra);

        let sensors: Sensors = Sensors { rays: rays };
        let mut serialized = ArrayTrait::new();
        sensors.serialize(ref serialized);
        serialized
    }
}
