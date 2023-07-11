use orion::operators::tensor::core::Tensor;
use orion::numbers::fixed_point::core::FixedType;

#[starknet::interface]
trait INN<T> {
    #[view]
    fn forward(self: @T, input: Tensor<FixedType>) -> usize;
}
