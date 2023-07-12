// This is a mock NN contract. It doesn't reflect a real neural network.
// TODO: write script to generate Starknet contract based on offchain trained model.
#[starknet::contract]
mod nn_mock {
    use array::{ArrayTrait, SpanTrait};

    use drive_ai::model::INN;

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

    use super::fc1::{fc1_bias, fc1_weights};

    #[storage]
    struct Storage {}

    fn forward(self: Tensor<FixedType>) -> usize {
        let w = fc1_weights();
        let b = fc1_bias();

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

        let x = self.quantize_linear(@y_scale, @y_zero_point);
        let x = NNTrait::linear(x, w, b);
        *x.argmax(0, Option::None(()), Option::None(())).data[0]
    }

    impl NNImpl of INN<ContractState> {
        fn forward(self: @ContractState, input: Tensor<FixedType>) -> usize {
            forward(input)
        }
    }
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
        shape.append(2);
        let mut data = ArrayTrait::new();
        data.append(i8 { mag: 1, sign: false });
        data.append(i8 { mag: 2, sign: true });
        data.append(i8 { mag: 3, sign: true });
        let extra = Option::<ExtraParams>::None(());
        TensorTrait::new(shape.span(), data.span(), extra)
    }
}

