use rand::Rng;
use serde::{Deserialize, Serialize};
use std::fs::File;
use std::io::Write;

const BRAIN_MUTATION_RATE: f32 = 5.0;
const BRAIN_MUTATION_VARIATION: f32 = 0.5;

#[derive(Clone, Serialize, Deserialize)]
pub struct Net {
    n_inputs: usize,
    layers: Vec<Layer>,
}

#[derive(Clone, Serialize, Deserialize)]
struct Layer {
    nodes: Vec<Vec<f64>>,
}

impl Net {
    pub fn new(layer_sizes: Vec<usize>) -> Self {
        if layer_sizes.len() < 2 {
            panic!("Need at least 2 layers");
        }
        for &size in layer_sizes.iter() {
            if size < 1 {
                panic!("Empty layers not allowed");
            }
        }

        let mut layers = Vec::new();
        let first_layer_size = *layer_sizes.first().unwrap();
        let mut prev_layer_size = first_layer_size;

        for &layer_size in layer_sizes[1..].iter() {
            layers.push(Layer::new(layer_size, prev_layer_size));
            prev_layer_size = layer_size;
        }

        Self {
            layers,
            n_inputs: first_layer_size,
        }
    }

    pub fn predict(&self, inputs: &Vec<f64>) -> Vec<Vec<f64>> {
        if inputs.len() != self.n_inputs {
            panic!("Bad input size");
        }

        let mut outputs = Vec::new();
        outputs.push(inputs.clone());
        for (layer_index, layer) in self.layers.iter().enumerate() {
            let layer_results = layer.predict(&outputs[layer_index]);
            outputs.push(layer_results);
        }

        outputs
    }

    pub fn mutate(&mut self) {
        self.layers.iter_mut().for_each(|l| l.mutate());
    }

    pub fn export_weights(&self) -> String {
        let mut quantized_net = self.clone();
        for layer in &mut quantized_net.layers {
            for node in &mut layer.nodes {
                for weight in node {
                    // Multiply the weight by 2**23 and keep only the integer part
                    *weight = (*weight * (2f64.powi(23))).floor();
                }
            }
        }
        serde_json::to_string(&quantized_net).unwrap()
    }

    // Export Cairo files given the current weights
    pub fn export_cairo_files(&self, dir_path: &str) -> std::io::Result<()> {
        let quantized_net = self.clone();
    
        // create file
        let file_name = format!("{}/model2.cairo", dir_path);
        let mut file = File::create(&file_name)?;
    
        // write general code
        writeln!(file, "#[system]")?;
        writeln!(file, "mod model {{")?;
        writeln!(file, "    use array::ArrayTrait;")?;
        writeln!(file, "    use dojo::world::Context;")?;
        writeln!(file, "    use drive_ai::racer::Sensors;")?;
        writeln!(file, "    use drive_ai::vehicle::{{Controls, Direction}};")?;
        writeln!(file, "    use orion::operators::nn::core::NNTrait;")?;
        writeln!(file, "    use orion::operators::nn::implementations::impl_nn_i8::NN_i8;")?;
        writeln!(file, "    use orion::operators::tensor::core::{{TensorTrait, ExtraParams, Tensor}};")?;
        writeln!(file, "    use orion::operators::tensor::implementations::impl_tensor_fp::Tensor_fp;")?;
        writeln!(file, "    use orion::operators::tensor::implementations::impl_tensor_i8::Tensor_i8;")?;
        writeln!(file, "    use orion::numbers::signed_integer::i8::i8;")?;
        writeln!(file, "    use orion::numbers::fixed_point::core::{{FixedType, FixedTrait}};")?;
        writeln!(file, "    use orion::performance::core::PerfomanceTrait;")?;
        writeln!(file, "    use orion::performance::implementations::impl_performance_fp::Performance_fp_i8;")?;
        writeln!(file, "    use orion::operators::nn::functional::linear::linear_ft::linear_ft;")?;
        writeln!(file, "    use core::traits::Into;")?;
        writeln!(file, "    use orion::numbers::fixed_point::implementations::impl_8x23::{{FP8x23Impl, ONE, FP8x23Mul}};")?;


        writeln!(file, "    fn execute(ctx: Context, sensors: Sensors) -> Controls {{")?;
        writeln!(file, "        let prediction: usize = forward(sensors.rays);")?;
        writeln!(file, "        let steer: Direction = if prediction == 0 {{")?;
        writeln!(file, "            Direction::Straight(())")?;
        writeln!(file, "        }} else if prediction == 1 {{")?;
        writeln!(file, "            Direction::Left(())")?;
        writeln!(file, "        }} else if prediction == 2 {{")?;
        writeln!(file, "            Direction::Right(())")?;
        writeln!(file, "        }} else {{")?;
        writeln!(file, "            let mut panic_msg = ArrayTrait::new();")?;
        writeln!(file, "            panic_msg.append('prediction must be < 3');")?;
        writeln!(file, "            panic(panic_msg)")?;
        writeln!(file, "        }};")?;
        writeln!(file, "        Controls {{ steer: steer,  }}")?;
        writeln!(file, "    }}")?;
        
        writeln!(file, "    fn forward(input: Tensor<FixedType>) -> usize {{")?;
        writeln!(file, "        let w = fc1::fc1_weights();")?;
        writeln!(file, "        let b = fc1::fc1_bias();")?;
        writeln!(file, "        let mut shape = ArrayTrait::<usize>::new();")?;
        writeln!(file, "        shape.append(1);")?;
        writeln!(file, "        let mut data = ArrayTrait::<FixedType>::new();")?;
        writeln!(file, "        data.append(FixedTrait::new_unscaled(1, false));")?;
        writeln!(file, "        let extra = Option::<ExtraParams>::None(());")?;
        writeln!(file, "        let y_scale = TensorTrait::new(shape.span(), data.span(), extra);")?;
        writeln!(file, "        let mut shape = ArrayTrait::<usize>::new();")?;
        writeln!(file, "        shape.append(1);")?;
        writeln!(file, "        let mut data = ArrayTrait::<FixedType>::new();")?;
        writeln!(file, "        data.append(FixedTrait::new_unscaled(0, false));")?;
        writeln!(file, "        let extra = Option::<ExtraParams>::None(());")?;
        writeln!(file, "        let y_zero_point = TensorTrait::new(shape.span(), data.span(), extra);")?;
        writeln!(file, "        let x = linear_ft(input, w, b);")?;
        writeln!(file, "        *x.argmax(0, Option::None(()), Option::None(())).data[0]")?;
        writeln!(file, "    }}")?;
    
        // iterate over layers to generate weights and biases
        for (layer_index, layer) in quantized_net.layers.iter().enumerate() {
            writeln!(file, "    mod fc{} {{", layer_index)?;
            writeln!(file, "        use array::ArrayTrait;")?;
            writeln!(file, "        use orion::operators::tensor::core::{{TensorTrait, Tensor, ExtraParams}};")?;
            writeln!(file, "        use orion::operators::tensor::implementations::impl_tensor_i8::Tensor_i8;")?;
            writeln!(file, "        use orion::numbers::fixed_point::core::FixedImpl;")?;
            writeln!(file, "        use orion::numbers::signed_integer::i8::i8;")?;
            writeln!(file, "        use orion::numbers::fixed_point::core::FixedType;")?;
            writeln!(file, "        use orion::operators::tensor::implementations::impl_tensor_fp::Tensor_fp;")?;
            writeln!(file, "        fn fc{}_weights() -> Tensor<FixedType> {{", layer_index)?;
            writeln!(file, "            let mut shape = ArrayTrait::<usize>::new();")?;
            writeln!(file, "            shape.append({});", layer.nodes.len())?;
            writeln!(file, "            shape.append({});", layer.nodes[0].len())?;
            writeln!(file, "            let mut data = ArrayTrait::<FixedType>::new();")?;
    
            // write data
            for node in &layer.nodes {
                for &weight in node {
                    let weight = (weight * (2f64.powi(23))).floor() as i32;
                    writeln!(file, "            data.append(FixedType {{ mag: {}, sign: {} }});", weight.abs(), weight.is_negative())?;
                }
            }
    
            // write footer of the weights function
            writeln!(file, "            let extra = Option::<ExtraParams>::None(());")?;
            writeln!(file, "            TensorTrait::new(shape.span(), data.span(), extra)")?;
            writeln!(file, "        }}")?;
    
            // create bias function for each layer with dummy values
            writeln!(file, "        fn fc{}_bias() -> Tensor<FixedType> {{", layer_index)?;
            writeln!(file, "            let mut shape = ArrayTrait::<usize>::new();")?;
            writeln!(file, "            shape.append(3);");
            writeln!(file, "            let mut data = ArrayTrait::<FixedType>::new();")?;
    
            // write dummy bias data
            for _ in 0..3 {
                writeln!(file, "            data.append(FixedType {{ mag: 0, sign: false }});");
            }
    
            // write footer of the bias function
            writeln!(file, "            let extra = Option::<ExtraParams>::None(());")?;
            writeln!(file, "            TensorTrait::new(shape.span(), data.span(), extra)")?;
            writeln!(file, "        }}")?;
    
            writeln!(file, "    }}")?;
        }
    
        // write footer of the model module
        writeln!(file, "}}")?;
    
        Ok(())
    }

}

impl Layer {
    fn new(layer_size: usize, prev_layer_size: usize) -> Self {
        let mut rng = rand::thread_rng();
        let mut nodes: Vec<Vec<f64>> = Vec::new();

        for _ in 0..layer_size {
            let mut node: Vec<f64> = Vec::new();
            for _ in 0..prev_layer_size + 1 {
                let random_weight: f64 = rng.gen_range(-1.0f64..1.0f64);
                node.push(random_weight);
            }
            nodes.push(node);
        }

        Self { nodes }
    }

    fn predict(&self, inputs: &Vec<f64>) -> Vec<f64> {
        let mut layer_results = Vec::new();
        for node in self.nodes.iter() {
            layer_results.push(self.sigmoid(self.dot_prod(&node, &inputs)));
        }

        layer_results
    }

    fn mutate(&mut self) {
        let mut rng = rand::thread_rng();
        for n in self.nodes.iter_mut() {
            for val in n.iter_mut() {
                if rng.gen_range(0.0..1.0) >= BRAIN_MUTATION_RATE {
                    continue;
                }

                *val += rng.gen_range(-BRAIN_MUTATION_VARIATION..BRAIN_MUTATION_VARIATION) as f64;
            }
        }
    }

    fn dot_prod(&self, node: &Vec<f64>, values: &Vec<f64>) -> f64 {
        let mut it = node.iter();
        let mut total = *it.next().unwrap();
        for (weight, value) in it.zip(values.iter()) {
            total += weight * value;
        }

        total
    }

    fn sigmoid(&self, y: f64) -> f64 {
        1f64 / (1f64 + (-y).exp())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_export_weights() {
        // create a new neural network
        let mut net = Net::new(vec![2, 3, 1]);

        // export the weights to a JSON string
        let weights = net.export_weights();

        // print the weights
        println!("Weights: {}", weights);

        // you can add assertions to check the output
        // for this example, we just check that the output is not empty
        assert!(!weights.is_empty());
    }

    #[test]
    fn test_export_cairo_weights() {
        // create a new neural network
        let mut net = Net::new(vec![2, 3, 1]);

        // export the weights to Cairo files
        net.export_cairo_files("src").unwrap();
    }
}